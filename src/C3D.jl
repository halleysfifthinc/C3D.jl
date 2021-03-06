module C3D

using Requires, VaxData

@enum Endian LE=1 BE=2

export readc3d,
       writetrc

export C3DFile

include("parameters.jl")
include("groups.jl")
include("header.jl")
include("validate.jl")

struct C3DFile
    name::String
    header::Header
    groups::Dict{Symbol, Group}
    point::Dict{String, Array{Union{Missing, Float32},2}}
    residual::Dict{String, Array{Union{Missing, Float32},1}}
    analog::Dict{String, Array{Float32,1}}
end

include("util.jl")

function C3DFile(name::String, header::Header, groups::Dict{Symbol,Group},
                 point::AbstractArray, residuals::AbstractArray, analog::AbstractArray;
                 missingpoints::Bool=true, strip_prefixes::Bool=false)
    fpoint = Dict{String,Array{Union{Missing, Float32},2}}()
    fresiduals = Dict{String,Array{Union{Missing, Float32},1}}()
    fanalog = Dict{String,Array{Float32,1}}()

    l = size(point, 1)
    allpoints = 1:l

    if strip_prefixes
        if haskey(groups, :SUBJECTS) && groups[:SUBJECTS][Int, :USES_PREFIXES] == 1
            rgx = Regex("("*join(groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES], '|')*
                        ")(?<label>\\w*)")
        else
            rgx = r":(?<label>\w*)"
        end
    end

    numpts = groups[:POINT][Int, :USED]
    if !iszero(numpts)
        for (idx, ptname) in enumerate(groups[:POINT][Vector{String}, :LABELS][1:numpts])
            if strip_prefixes
                m = match(rgx, ptname)
                if !isnothing(m) && !isnothing(m[:label])
                    ptname = m[:label]
                end
            end

            fpoint[ptname] = point[:,((idx-1)*3+1):((idx-1)*3+3)]
            fresiduals[ptname] = residuals[:,idx]
            if missingpoints
                invalidpoints = findall(x -> x === -1.0f0, fresiduals[ptname])
                calculatedpoints = findall(iszero, fresiduals[ptname])
                goodpoints = setdiff(allpoints, invalidpoints ∪ calculatedpoints)
                fpoint[ptname][invalidpoints, :] .= missing
                fresiduals[ptname][goodpoints] = calcresiduals(fresiduals[ptname], abs(groups[:POINT][Float32, :SCALE]))[goodpoints]
                fresiduals[ptname][invalidpoints] .= missing
                fresiduals[ptname][calculatedpoints] .= 0.0f0
            end
        end
    end

    if !iszero(groups[:ANALOG][Int, :USED])
        for (idx, name) in enumerate(groups[:ANALOG][Vector{String}, :LABELS][1:groups[:ANALOG][Int, :USED]])
            fanalog[name] = analog[:, idx]
        end
    end

    return C3DFile(name, header, groups, fpoint, fresiduals, fanalog)
end

function Base.show(io::IO, f::C3DFile)
    if get(io, :compact, true)
        print(io, "C3DFile(\"", f.name, "\")")
    else
        length = (f.groups[:POINT][Int, :FRAMES] == typemax(UInt16)) ?
            f.groups[:POINT][Int, :LONG_FRAMES] :
            f.groups[:POINT][Int, :FRAMES]

        print(io, "C3DFile(\"", f.name, "\", ",
              length, "sec, ",
              f.groups[:POINT][Int, :USED], " points, ",
              f.groups[:ANALOG][Int, :USED], " analog channels)")
    end
end

function calcresiduals(x::AbstractVector, scale)
    residuals = (reinterpret.(UInt32, x) .>> 16) .& 0xff .* scale
end

function readdata(io::IOStream, groups::Dict{Symbol,Group}, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    seek(io, (groups[:POINT][Int, :DATA_START]-1)*512)

    format = groups[:POINT][Float32, :SCALE] > 0 ? Int16 : FType

    # Read data in a transposed structure for better read/write speeds due to Julia being
    # column-order arrays
    numframes::Int = groups[:POINT][Int, :FRAMES]
    if numframes == typemax(UInt16) && haskey(groups, :TRIAL) && haskey(groups[:TRIAL][:params], :ACTUAL_END_FIELD)
        numframes = only(reinterpret(Int32, groups[:TRIAL][Vector{Int16}, :ACTUAL_END_FIELD]))
    end
    nummarkers = groups[:POINT][Int, :USED]
    hasmarkers = !iszero(nummarkers)
    if hasmarkers
        point = Array{Float32,2}(undef, nummarkers*3, numframes)
        residuals = Array{Float32,2}(undef, nummarkers, numframes)

        nb = nummarkers*4
        pointidxs = filter(x -> x % 4 != 0, 1:nb)
        residxs = filter(x -> x % 4 == 0, 1:nb)

        pointtmp = Vector{format}(undef, nb)
        pointview = view(pointtmp, pointidxs)
        resview = view(pointtmp, residxs)
    else
        point = Array{Float32,2}(undef, 0,0)
        residuals = Array{Float32,2}(undef, 0,0)
    end

    numchannels = groups[:ANALOG][Int, :USED]
    haschannels = !iszero(numchannels)
    if haschannels
        # Analog Samples Per Frame => ASPF
        aspf = convert(Int, groups[:ANALOG][Float32, :RATE]/groups[:POINT][Float32, :RATE])
        analog = Array{Float32,2}(undef, numchannels, aspf*numframes)

        analogtmp = Matrix{format}(undef, (numchannels,aspf))
    else
        analog = Array{Float32,2}(undef, 0,0)
    end

    @inbounds for i in 1:numframes
        if hasmarkers
            saferead!(io, pointtmp, FEND)
            point[:,i] = pointview
            residuals[:,i] = resview
        end
        if haschannels
            saferead!(io, analogtmp, FEND)
            analog[:,((i-1)*aspf+1):(i*aspf)] = analogtmp
        end
    end

    if hasmarkers && format == Int16
        # Multiply or divide by [:point][:scale]
        POINT_SCALE = groups[:POINT][Float32, :SCALE]
        point .*= abs(POINT_SCALE)
    end

    if haschannels
        if numchannels == 1
            ANALOG_OFFSET = groups[:ANALOG][Float32, :OFFSET]
            SCALE = (groups[:ANALOG][Float32, :GEN_SCALE] * groups[:ANALOG][Float32, :SCALE])
            analog .= (analog .- ANALOG_OFFSET) .* SCALE
        else
            VECANALOG_OFFSET = groups[:ANALOG][Vector{Int}, :OFFSET][1:numchannels]
            VECSCALE = groups[:ANALOG][Float32, :GEN_SCALE] .*
                            groups[:ANALOG][Vector{Float32}, :SCALE][1:numchannels]

            analog .= (analog .- VECANALOG_OFFSET) .* VECSCALE
        end
    end

    return (permutedims(point), permutedims(residuals), permutedims(analog))
end

function saferead(io::IOStream, ::Type{T}, FEND::Endian) where T
    if FEND == LE
        return ltoh(read(io, T))
    else
        return ntoh(read(io, T))
    end
end

function saferead!(io::IOStream, x::AbstractArray, FEND::Endian)
    if FEND == LE
        x .= ltoh.(read!(io, x))
    else
        x .= ntoh.(read!(io, x))
    end
    nothing
end

function saferead(io::IOStream, ::Type{T}, FEND::Endian, dims)::Array{T} where T
    if FEND == LE
        return ltoh.(read!(io, Array{T}(undef, dims)))
    else
        return ntoh.(read!(io, Array{T}(undef, dims)))
    end
end

function saferead(io::IOStream, ::Type{VaxFloatF}, FEND::Endian)::Float32
    if FEND == LE
        return convert(Float32, ltoh(read(io, VaxFloatF)))
    else
        return convert(Float32, ntoh(read(io, VaxFloatF)))
    end
end

function saferead(io::IOStream, ::Type{VaxFloatF}, FEND::Endian, dims::NTuple{N,Int})::Array{Float32,N} where N
    if FEND == LE
        return convert(Array{Float32,N}, ltoh.(read!(io, Array{VaxFloatF}(undef, dims))))
    else
        return convert(Array{Float32,N}, ntoh.(read!(io, Array{VaxFloatF}(undef, dims))))
    end
end

"""
    readc3d(fn)

Read the C3D file at `fn`.

# Keyword arguments
- `paramsonly::Bool = false`: Only reads the header and parameters
- `validateparams::Bool = true`: Validates parameters against C3D requirements
- `missingpoints::Bool = true`: Sets invalid points to `missing`
"""
function readc3d(fn::AbstractString; paramsonly=false, validate=true,
                 missingpoints=true, strip_prefixes=false)
    if !isfile(fn)
        error("File ", fn, " cannot be found")
    end

    io = open(fn, "r")

    groups, header, FEND, FType = _readparams(fn, io)

    if validate
        validatec3d(header, groups)
    end

    if paramsonly
        point = Dict{String,Array{Union{Missing, Float32},2}}()
        residual = Dict{String,Array{Union{Missing, Float32},1}}()
        analog = Dict{String,Array{Float32,1}}()
    else
        (point, residual, analog) = readdata(io, groups, FEND, FType)
    end

    close(io)

    res = C3DFile(fn, header, groups, point, residual, analog;
                  missingpoints, strip_prefixes)

    return res
end

function _readparams(fn::String, io::IOStream)
    params_ptr = read(io, UInt8)

    if read(io, UInt8) != 0x50
        error("File ", fn, " is not a valid C3D file")
    end

    # Jump to parameters block
    seek(io, (params_ptr - 1) * 512)

    # Skip 2 reserved bytes
    # TODO: store bytes for saving modified files
    skip(io, 2)

    paramblocks = read(io, UInt8)
    proctype = read(io, Int8) - 83

    FType = Float32

    # Deal with host big-endianness in the future
    if proctype == 1
        # little-endian
        FEND = LE
    elseif proctype == 2
        # DEC floats; little-endian
        FType = VaxFloatF
        FEND = LE
    elseif proctype == 3
        # big-endian
        FEND = BE
    else
        error("Malformed processor type. Expected 1, 2, or 3. Found ", proctype)
    end

    mark(io)
    header = readheader(io, FEND, FType)
    reset(io)
    unmark(io)

    gs = Array{Group,1}()
    ps = Array{Parameter,1}()
    moreparams = true
    fail = 0
    np = 0

    skip(io, 1)
    if read(io, Int8) < 0
        # Group
        skip(io, -2)
        push!(gs, readgroup(io, FEND, FType))
        np = gs[end].pos + gs[end].np + abs(gs[end].nl) + 2
        moreparams = gs[end].np != 0 ? true : false
    else
        # Parameter
        skip(io, -2)
        push!(ps, readparam(io, FEND, FType))
        np = ps[end].pos + ps[end].np + abs(ps[end].nl) + 2
        moreparams = ps[end].np != 0 ? true : false
    end

    while moreparams
        # Mark current position in file in case the pointer is incorrect
        mark(io)
        if fail === 0 && np != position(io)
                # @debug "Pointer mismatch at position $(position(io)) where pointer was $np"
                seek(io, np)
        elseif fail > 1 # this is the second failed attempt
            # @debug "Second failed parameter read attempt from $(position(io))"
            break
        end

        # Read the next two bytes to get the gid
        skip(io, 1)
        local gid = read(io, Int8)
        if gid < 0 # Group
            # Reset to the beginning of the group
            skip(io, -2)
            try
                push!(gs, readgroup(io, FEND, FType))
                np = gs[end].pos + gs[end].np + abs(gs[end].nl) + 2
                moreparams = gs[end].np != 0 ? true : false # break if the pointer is 0 (ie the parameters are finished)
                fail = 0 # reset fail counter following a successful read
            catch e
                # Last readgroup failed, possibly due to a bad pointer. Reset to the ending
                # location of the last successfully read parameter and try again. Count the failure.
                reset(io)
                # @debug "Read group failed, last parameter ended at $(position(io)), pointer at $np" fail
                fail += 1
            finally
                unmark(io) # Unmark the file regardless
            end
        elseif gid > 0 # Parameter
            # Reset to the beginning of the parameter
            skip(io, -2)
            try
                push!(ps, readparam(io, FEND, FType))
                np = ps[end].pos + ps[end].np + abs(ps[end].nl) + 2
                moreparams = ps[end].np != 0 ? true : false
                fail = 0
            catch e
                reset(io)
                # @debug "Read group failed, last parameter ended at $(position(io)), pointer at $np" fail
                fail += 1
            finally
                unmark(io)
            end
        else # Last parameter pointer is incorrect (assumption)
            # The group ID should never be zero, if it is, the most likely explanation is
            # that the pointer is incorrect (eg the pointer was not fixed when the previously
            # last parameter was deleted or moved)
            # @debug "Bad last position. Assuming parameter section is finished."
            break
        end
    end

    groups = Dict{Symbol,Group}()
    gids = Dict{Int8,Symbol}()

    for group in gs
        groups[group.symname] = group
        gids[abs(group.gid)] = group.symname
    end

    for param in ps
        groups[gids[param.gid]].params[param.symname] = param
    end

    return (groups, header, FEND, FType)
end

function __init__()
    @require DatasetManager="2ca6b172-e30b-458d-964f-9c975788bc07" include("dataset-source.jl")
end

end # module
