module C3D

using VaxData

@enum Endian LE=1 BE=2

export readc3d, readparams

export C3DFile

include("parameters.jl")
include("groups.jl")
include("header.jl")
include("validate.jl")

struct C3DFile
    name::String
    header::Header
    groups::Dict{Symbol,Group}
    point::Dict{String,Array{Union{Missing, Float32},2}}
    residuals::Dict{String, Array{Float32,1}}
    analog::Dict{String,Array{Float32,1}}
end

function C3DFile(name::String, header::Header, groups::Dict{Symbol,Group},
                 point::AbstractArray, residuals::AbstractArray, analog::AbstractArray;
                 withmissings::Bool=true)
    fpoint = Dict{String,Array{Union{Missing, Float32},2}}()
    fresiduals = Dict{String,Array{Float32,1}}()
    fanalog = Dict{String,Array{Float32,1}}()

    if !iszero(groups[:POINT].USED)
        for (idx, symname) in enumerate(groups[:POINT].LABELS[1:groups[:POINT].USED])
            fpoint[symname] = point[:,((idx-1)*3+1):((idx-1)*3+3)]
            fresiduals[symname] = residuals[:,idx]
            if withmissings
                fpoint[symname][findall(x -> x == -1.0, fresiduals[symname]), :] .= missing
            end
        end
    end

    if !iszero(groups[:ANALOG].USED)
        for (idx, symname) in enumerate(groups[:ANALOG].LABELS[1:groups[:ANALOG].USED])
            fanalog[symname] = analog[:, idx]
        end
    end

    return C3DFile(name, header, groups, fpoint, fresiduals, fanalog)
end

function Base.show(io::IO, f::C3DFile)
    if get(io, :compact, true)
        print(io, "C3DFile(\"", f.name, "\")")
    else
        length = (f.groups[:POINT].FRAMES == typemax(UInt16)) ?
            f.groups[:POINT].LONG_FRAMES :
            f.groups[:POINT].FRAMES

        print(io, "C3DFile(\"", f.name, "\", ",
              length, "sec, ",
              f.groups[:POINT].USED, " points, ",
              f.groups[:ANALOG].USED, " analog channels)")
    end
end

function readdata(f::IOStream, groups::Dict{Symbol,Group}, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    seek(f, (groups[:POINT].DATA_START-1)*512)

    format = groups[:POINT].SCALE > 0 ? Int16 : FType

    # Read data in a transposed structure for better read/write speeds due to Julia being
    # column-order arrays
    numframes = convert(Int, groups[:POINT].FRAMES)
    if numframes == typemax(UInt16) && haskey(groups, :TRIAL) && haskey(groups[:TRIAL].params, :ACTUAL_END_FIELD)
        numframes = convert(Int, reinterpret(Int32, groups[:TRIAL].ACTUAL_END_FIELD)[1])
    end
    nummarkers = convert(Int, groups[:POINT].USED)
    hasmarkers = !iszero(nummarkers)
    if hasmarkers
        point = Array{Float32,2}(undef, nummarkers*3, numframes)
        residuals = Array{Float32,2}(undef, nummarkers, numframes)

        nb = nummarkers*4
        pointidxs = filter(x -> x % 4 != 0, 1:nb)
        residxs = filter(x -> x % 4 == 0, 1:nb)

        pointtmp = Array{format}(undef, nb)
        pointview = view(pointtmp, pointidxs)
        resview = view(pointtmp, residxs)
    else
        point = Array{Float32,2}(undef, 0,0)
        residuals = Array{Float32,2}(undef, 0,0)
    end

    numchannels = convert(Int, groups[:ANALOG].USED)
    haschannels = !iszero(numchannels)
    if haschannels
        # Analog Samples Per Frame => ASPF
        aspf = convert(Int, groups[:ANALOG].RATE/groups[:POINT].RATE)
        analog = Array{Float32,2}(undef, numchannels, aspf*numframes)

        analogtmp = Array{format}(undef, (numchannels,aspf))
    else
        analog = Array{Float32,2}(undef, 0,0)
    end

    @inbounds for i in 1:numframes
        if hasmarkers
            saferead!(f, pointtmp, FEND)
            point[:,i] = convert.(Float32, pointview) # Convert from `format` (eg Int16 or FType)
            residuals[:,i] = convert.(Float32, resview)
        end
        if haschannels
            saferead!(f, analogtmp, FEND)
            analog[:,((i-1)*aspf+1):(i*aspf)] = convert.(Float32, analogtmp)
        end
    end

    if hasmarkers && format == Int16
        # Multiply or divide by [:point][:scale]
        point .*= abs(groups[:POINT].SCALE)
    end

    if haschannels
        if numchannels == 1
            analog[:] = (analog .- groups[:ANALOG].OFFSET) .*
                        (groups[:ANALOG].GEN_SCALE * groups[:ANALOG].SCALE)
        else
            analog[:] = (analog .- groups[:ANALOG].OFFSET[1:numchannels]) .*
                        groups[:ANALOG].GEN_SCALE .*
                        groups[:ANALOG].SCALE[1:numchannels]
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

function saferead(io::IOStream, ::Type{VaxFloatF}, FEND::Endian, dims)::Array{Float32}
    if FEND == LE
        return convert.(Float32, ltoh.(read!(io, Array{VaxFloatF}(undef, dims))))
    else
        return convert.(Float32, ntoh.(read!(io, Array{VaxFloatF}(undef, dims))))
    end
end

"""
    readc3d(fn; withmissings=true)

Read the C3D file `fn`. Keyword argument `withmissings` replaces invalid data points with
`missing` values.

See also: [`readc3dinfo`](@ref)
"""
function readc3d(fn::AbstractString; withmissings=true)
    if !isfile(fn)
        error("File ", fn, " cannot be found")
    end

    f = open(fn, "r")

    groups, header, FEND, FType = _readparams(f)

    validate(header, groups, complete=false)

    (point, residuals, analog) = readdata(f, groups, FEND, FType)

    res = C3DFile(fn, header, groups, point, residuals, analog; withmissings=withmissings)

    close(f)

    return res
end

function _readparams(f::IOStream)
    params_ptr = read(f, UInt8)

    if read(f, UInt8) != 0x50
        error("File ", fn, " is not a valid C3D file")
    end

    # Jump to parameters block
    seek(f, (params_ptr - 1) * 512)

    # Skip 2 reserved bytes
    # TODO: store bytes for saving modified files
    read(f, UInt16)

    paramblocks = read(f, UInt8)
    proctype = read(f, Int8) - 83

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

    mark(f)
    header = readheader(f, FEND, FType)
    reset(f)
    unmark(f)

    gs = Array{Group,1}()
    ps = Array{AbstractParameter,1}()
    moreparams = true
    lastparam = :GROUP
    fail = 0
    np = 0

    read(f, UInt8)
    if read(f, Int8) < 0
        # Group
        skip(f, -2)
        push!(gs, readgroup(f, FEND, FType))
        moreparams = gs[end].np != 0 ? true : false
        lastparam = :GROUP
    else
        # Parameter
        skip(f, -2)
        push!(ps, readparam(f, FEND, FType))
        moreparams = ps[end].np != 0 ? true : false
        lastparam = :PARAM
    end

    while moreparams
        # Mark current position in file in case the pointer is incorrect
        mark(f)
        if lastparam == :GROUP
            np = gs[end].pos + gs[end].np + abs(gs[end].nl) + 2
            # Only seek if necessary
            if np != position(f)
                @debug "Pointer mismatch at position $(position(f)) where pointer was $np"
                seek(f, np)
            end
        elseif lastparam == :PARAM
            np = ps[end].pos + ps[end].np + abs(ps[end].nl) + 2
            if np != position(f)
                @debug "Pointer mismatch at position $(position(f)) where pointer was $np"
                seek(f, np)
            end
        elseif fail > 1 # lasparam == :NOP is a given at this point, this is the second failed attempt
            @debug "Second failed parameter read attempt from $(position(f))"
            break
        end

        # Read the next two bytes to get the gid
        read(f, UInt8)
        local gid = read(f, Int8)
        if gid < 0 # Group
            # Reset to the beginning of the group
            skip(f, -2)
            try
              push!(gs, readgroup(f, FEND, FType))
              moreparams = gs[end].np != 0 ? true : false # break if the pointer is 0 (ie the parameters are finished)
              lastparam = :GROUP
            catch e
                # Last readgroup failed, possibly due to a bad pointer. Reset to the ending
                # location of the last successfully read parameter and try again. Note the failure.
                reset(f)
                @debug "Read group failed, last parameter ended at $(position(f)), pointer at $np" fail
                lastparam = :NOP
                fail += 1
            finally
                unmark(f) # Unmark the file regardless
            end
        elseif gid > 0 # Parameter
            # Reset to the beginning of the parameter
            skip(f, -2)
            try
              push!(ps, readparam(f, FEND, FType))
              moreparams = ps[end].np != 0 ? true : false
              lastparam = :PARAM
            catch e
                reset(f)
                @debug "Read group failed, last parameter ended at $(position(f)), pointer at $np" fail
                lastparam = :NOP
                fail += 1
            finally
                unmark(f)
            end
        else # Last parameter pointer is incorrect (assumption)
            # The group ID should never be zero, if it is, the most likely explanation is
            # that the pointer is incorrect (eg the pointer was not fixed when the previously
            # last parameter was deleted or moved)
            @debug "Bad last position. Assuming parameter section is finished."
            break
        end
    end

    groups = Dict{Symbol,Group}()
    gids = Dict{Int,Symbol}()

    for group in gs
        groups[group.symname] = group
        gids[abs(group.gid)] = group.symname
    end

    for param in ps
        groups[gids[param.gid]].params[param.symname] = param
    end

    return (groups, header, FEND, FType)
end

"""
    readc3dinfo(fn; validate=true)

Only read the C3D file header and parameters.

See also: [`readc3d`](@ref)
"""
function readc3dinfo(fn::AbstractString; validate=true)
    if !isfile(fn)
        error("File ", fn, " cannot be found")
    end

    f = open(fn, "r")

    groups, header, FEND, FType = _readparams(f)

    if validate
        validate(header, groups, complete=false)
    end

    close(f)

    return groups
end

end # module
