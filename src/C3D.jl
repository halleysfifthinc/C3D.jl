module C3D

using VaxData, PrecompileTools, LazyArtifacts, Dates

abstract type AbstractEndian{T} end
struct LittleEndian{T} <: AbstractEndian{T} end
struct BigEndian{T} <: AbstractEndian{T} end
const LE = LittleEndian
const BE = BigEndian

Base.eltype(::Type{<:AbstractEndian{T}}) where {T} = T
(::Type{<:LE{T}})(::Type{NT}) where {T,NT} = LE{NT}
(::Type{<:BE{T}})(::Type{NT}) where {T,NT} = BE{NT}
(::Type{<:LE{T}})(::Type{OT}) where {T,OT<:AbstractEndian} = LE{eltype(OT)}
(::Type{<:BE{T}})(::Type{OT}) where {T,OT<:AbstractEndian} = BE{eltype(OT)}

export readc3d, numpointframes, numanalogframes, writetrc

export C3DFile

include("parameters.jl")
include("groups.jl")
include("header.jl")
include("validate.jl")

struct C3DFile{END<:AbstractEndian}
    name::String
    header::Header{END}
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
    numpts = groups[:POINT][Int, :USED]

    if strip_prefixes
        if haskey(groups, :SUBJECTS) && groups[:SUBJECTS][Int, :USES_PREFIXES] == 1
            rgx = Regex("("*join(groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES], '|')*
                        ")(?<label>\\w*)")
        else
            rgx = r":(?<label>\w*)"
        end
        allunique(map(x -> something(something(match(rgx, x), (;label=nothing))[:label], x),
            groups[:POINT][Vector{String}, :LABELS][1:numpts])) ||
            throw(ArgumentError("marker names would not be unique after removing subject prefixes"))
    end

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

C3DFile(fn::AbstractString) = readc3d(string(fn))

numpointframes(f::C3DFile) = numpointframes(f.groups)

function numpointframes(groups::Dict{Symbol,Group})::Int
    numframes::Int = groups[:POINT][Int, :FRAMES]
    if haskey(groups[:POINT], :LONG_FRAMES)
        if typeof(groups[:POINT][:LONG_FRAMES]) <: Vector{Int16}
            pointlongframes = only(reinterpret(Int32, groups[:POINT][Vector{Int16}, :LONG_FRAMES]))
        else
            pointlongframes = convert(Int, groups[:POINT][Float32, :LONG_FRAMES])
        end
        if numframes ≤ typemax(UInt16) && numframes != pointlongframes
            @debug "file may be misformatted. POINT:FRAMES ($numframes) != POINT:LONG_FRAMES ($pointlongframes)"
        end
        numframes = pointlongframes
    end
    if haskey(groups, :TRIAL) && haskey(groups[:TRIAL], :ACTUAL_START_FIELD) &&
        haskey(groups[:TRIAL], :ACTUAL_END_FIELD)
        trial_startend_field = only(reinterpret(UInt32,
                                    groups[:TRIAL][Vector{Int16}, :ACTUAL_END_FIELD])) -
                               only(reinterpret(UInt32,
                                    groups[:TRIAL][Vector{Int16}, :ACTUAL_START_FIELD])) + 1
        if numframes ≤ typemax(UInt16) && numframes != trial_startend_field
            @debug "file may be misformatted. POINT:FRAMES ($numframes) != POINT:LONG_FRAMES ($trial_startend_field)"
        end
        numframes = trial_startend_field
    end
    return numframes
end

function numanalogframes(f::C3DFile)
    if iszero(f.groups[:ANALOG][Int, :USED])
        return 0
    else
        aspf = convert(Int, f.groups[:ANALOG][Float32, :RATE] /
                            f.groups[:POINT][Float32, :RATE])
        return numpointframes(f)*aspf
    end
end

function Base.show(io::IO, f::C3DFile)
    dispwidth = textwidth(f.name) + 11
    cols = displaysize(io)[2] - 11
    pathcomps = splitpath(f.name)

    if dispwidth > cols
        if first(pathcomps) == "/"
            i = 2
        else
            i = 1
        end
        while length(joinpath(["…/"; pathcomps[i:end]])) > cols && i+1 < length(pathcomps)
            i += 1
        end
        name = joinpath(pathcomps[i+1:end])
        if i > 1
            name = joinpath("…/", name)
        end
    else
        name = f.name
    end

    print(io, "C3DFile(\"", name, "\")")
end

const RST = "\e[39m"
const GRY = "\e[37m"

function Base.show(io::IO, ::MIME"text/plain", f::C3DFile)
    nframes = numpointframes(f)
    fs = round(Int, f.groups[:POINT][Float32, :RATE])

    rem_frames = round(Int, rem(nframes, fs))
    rem_str = rem_frames > 0 ? '+'*lpad(rem_frames, ndigits(fs - 1), '0') : ""
    nframes -= rem_frames

    tim = canonicalize(Dates.CompoundPeriod(Second(fld(nframes,fs))))

    println(io, f)
    print(io, "  Duration: ")
    if nframes == 0 # Duration less than a second
        print(io, "0")
    else
        join(io, [Dates.value(first(tim.periods));
            lpad.(Dates.value.(Iterators.rest(tim.periods, 2)), 2, '0')], ':')
    end
    print(io, rem_str, " $GRY")
    if nframes > 0 && maximum(tim.periods) isa Hour
        print(io, "hh:mm:ss")
    elseif nframes > 0 && maximum(tim.periods) isa Minute
        print(io, "mm:ss")
    else
        print(io, nframes > 0 ?
            's'^ndigits(Dates.value(first(filter(x -> x isa Second, tim.periods)))) : "s")
    end
    if rem_frames > 0
        print(io, "+", 'f'^ndigits(fs-1), "$RST\n  ")
    else
        print(io, "$RST\n  ")
    end

    if f.groups[:POINT][:USED] > 0
        print(io, f.groups[:POINT][Int, :USED], "$GRY points$RST ",
            "@ $(round(Int, fs))$GRY Hz$RST")
      end
    if f.groups[:ANALOG][:USED] > 0
        if f.groups[:POINT][:USED] > 0
            print(io, "; ")
        end
        print(io, f.groups[:ANALOG][Int, :USED], "$GRY analog channels$RST ",
              "@ $(round(Int, f.groups[:ANALOG][:RATE]))$GRY Hz$RST")
    end
end

function calcresiduals(x::AbstractVector, scale)
    return (reinterpret.(UInt32, x) .>> 16) .& 0xff .* scale
end

function readdata(
    io::IOStream, head::Header, groups::Dict{Symbol,Group}, ::Type{END}
    ) where {END<:AbstractEndian}
    seek(io, (groups[:POINT][Int, :DATA_START]-1)*512)

    format = groups[:POINT][Float32, :SCALE] > 0 ? Int16 : eltype(END)

    numframes::Int = numpointframes(groups)
    nummarkers::Int = groups[:POINT][Int, :USED]
    numchannels::Int = groups[:ANALOG][Int, :USED]
    aspf::Int = convert(Int, get(groups[:ANALOG], (Float32, :RATE), get(groups[:POINT], (Float32, :RATE), head.pointrate))/
        get(groups[:POINT], (Float32, :RATE), head.pointrate))

    est_data_size = numframes*sizeof(format)*(nummarkers*4 + numchannels*aspf)
    rem_file_size = stat(fd(io)).size - position(io)
    @debug "Estimated DATA size: $(Base.format_bytes(est_data_size)); \
        remaining file data: $(Base.format_bytes(rem_file_size))"
    if est_data_size > rem_file_size
        # Some combination of numframes, nummarkers, numchannels, aspf, or format is wrong
        # Check any duplicated info and use instead
        #
        if nummarkers > head.npoints
            # Needed to correctly read artifact"sample27/kyowadengyo.c3d"
            nummarkers = head.npoints
            groups[:POINT].params[:USED].payload.data = nummarkers
        end

        # Remaining checks will be withheld until triggering test cases are demonstrated
        # if aspf > head.aspf
        #     aspf = head.aspf
        # end
        # if numchannels > head.ampf/aspf
        #     numchannels = head.ampf/aspf
        # end
    end

    # Read data in a transposed structure for better read/write speeds due to Julia being
    # column-order arrays
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

    haschannels = !iszero(numchannels)
    if haschannels
        # Analog Samples Per Frame => ASPF
        analog = Array{Float32,2}(undef, numchannels, aspf*numframes)

        analogtmp = Matrix{format}(undef, (numchannels,aspf))
    else
        analog = Array{Float32,2}(undef, 0,0)
    end

    @inbounds for i in 1:numframes
        if hasmarkers
            read!(io, pointtmp, END)
            point[:,i] = pointview # convert's `pointtmp` element type in `setindex`
            residuals[:,i] = resview # ditto
        end
        if haschannels
            read!(io, analogtmp, END)
            analog[:,((i-1)*aspf+1):(i*aspf)] = analogtmp # ditto
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
            SCALE = groups[:ANALOG][Float32, :GEN_SCALE] * groups[:ANALOG][Float32, :SCALE]
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

function Base.read(io::IO, ::Type{LittleEndian{T}}) where T
    return ltoh(read(io, T))
end

function Base.read(io::IO, ::Type{BigEndian{T}}) where T
    return ntoh(read(io, T))
end

function Base.read(io::IO, ::Type{LittleEndian{VaxFloatF}})
    return convert(Float32, ltoh(read(io, VaxFloatF)))
end

function Base.read(io::IO, ::Type{BigEndian{VaxFloatF}})
    return convert(Float32, ntoh(read(io, VaxFloatF)))
end

function Base.read!(io::IO, a::AbstractArray{T}, ::Type{<:LittleEndian{U}}) where {T,U}
    read!(io, a)
    a .= ltoh.(a)
    return a
end

function Base.read!(io::IO, a::AbstractArray{T}, ::Type{<:BigEndian{U}}) where {T,U}
    read!(io, a)
    a .= ntoh.(a)
    return a
end

function Base.read!(io::IO, a::AbstractArray{Float32}, ::Type{LittleEndian{VaxFloatF}})
    _a = read!(io, similar(a, VaxFloatF))
    a .= convert.(Float32, ltoh.(_a))
    return a
end

function Base.read!(io::IO, a::AbstractArray{Float32}, ::Type{BigEndian{VaxFloatF}})
    _a = read!(io, similar(a, VaxFloatF))
    a .= convert.(Float32, ntoh.(_a))
    return a
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
    io = open(fn, "r")

    groups, header, END = _readparams(fn, io)

    if validate
        validatec3d(header, groups)
    end

    if paramsonly
        point = Dict{String,Array{Union{Missing, Float32},2}}()
        residual = Dict{String,Array{Union{Missing, Float32},1}}()
        analog = Dict{String,Array{Float32,1}}()
        close(io)
        return C3DFile(fn, header, groups, point, residual, analog)
    else
        (point, residual, analog) = readdata(io, header, groups, END)
        close(io)
    end

    res = C3DFile(fn, header, groups, point, residual, analog;
                  missingpoints, strip_prefixes)

    return res
end

function _readparams(fn::String, io::IO)
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
        END = LE{FType}
    elseif proctype == 2
        # DEC floats; little-endian
        FType = VaxFloatF
        END = LE{FType}
    elseif proctype == 3
        # big-endian
        END = BE{FType}
    else
        error("Malformed processor type. Expected 1, 2, or 3. Found ", proctype)
    end

    mark(io)
    header = read(io, Header{END})
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
        push!(gs, read(io, Group{END}))
        np = gs[end].pos + gs[end].np + length(gs[end]._name) + 2
        moreparams = gs[end].np != 0 ? true : false
    else
        # Parameter
        skip(io, -2)
        push!(ps, readparam(io, END))
        np = ps[end].pos + ps[end].np + length(ps[end]._name) + 2
        moreparams = ps[end].np != 0 ? true : false
    end

    while moreparams
        # Mark current position in file in case the pointer is incorrect
        mark(io)
        if fail === 0 && np != position(io)
                @debug "Pointer mismatch at position $(position(io)) where pointer was $np"
                seek(io, np)
        elseif fail > 1 # this is the second failed attempt
            @debug "Second failed parameter read attempt from $(position(io))"
            break
        end

        # Read the next two bytes to get the gid
        skip(io, 1)
        local gid = read(io, Int8)
        if gid < 0 # Group
            # Reset to the beginning of the group
            skip(io, -2)
            try
                push!(gs, read(io, Group{END}))
                np = gs[end].pos + gs[end].np + length(gs[end]._name) + 2
                moreparams = gs[end].np != 0 ? true : false # break if the pointer is 0 (ie the parameters are finished)
                fail = 0 # reset fail counter following a successful read
            catch e
                # Last readgroup failed, possibly due to a bad pointer. Reset to the ending
                # location of the last successfully read parameter and try again. Count the failure.
                reset(io)
                @debug "Read group failed, last parameter ended at $(position(io)), pointer at $np" fail exception=(e,backtrace())
                fail += 1
            finally
                unmark(io) # Unmark the file regardless
            end
        elseif gid > 0 # Parameter
            # Reset to the beginning of the parameter
            skip(io, -2)
            try
                push!(ps, readparam(io, END))
                np = ps[end].pos + ps[end].np + length(ps[end]._name) + 2
                moreparams = ps[end].np != 0 ? true : false
                fail = 0
            catch e
                reset(io)
                @debug "Read group failed, last parameter ended at $(position(io)), pointer at $np" fail exception=(e,backtrace())
                fail += 1
            finally
                unmark(io)
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
    gids = Dict{Int8,Symbol}()

    for group in gs
        groups[group.name] = group
        gids[abs(group.gid)] = group.name
    end

    for param in ps
        if haskey(gids, param.gid)
            groups[gids[param.gid]].params[param.name] = param
        else
            groupsym = Symbol("GID_$(param.gid)_MISSING")
            if !haskey(groups, groupsym)
                groupname = string(groupsym)
                groups[groupsym] = Group{END}(groupname, "Group was not defined in header"; gid=param.gid)
            end
            groups[groupsym].params[param.name] = param
        end
    end

    return (groups, header, END)
end

@setup_workload begin
    path, io = mktemp()
    close(io)
    @compile_workload begin
        f = readc3d(joinpath(artifact"sample01", "Eb015pr.c3d"))
            readc3d(joinpath(artifact"sample01", "Eb015pi.c3d"))
            readc3d(joinpath(artifact"sample01", "Eb015sr.c3d"))
            readc3d(joinpath(artifact"sample01", "Eb015si.c3d"))
            readc3d(joinpath(artifact"sample01", "Eb015vr.c3d"))
            readc3d(joinpath(artifact"sample01", "Eb015vi.c3d"))
        show(devnull, f)
        show(devnull, MIME("text/plain"), f)
        writetrc(path, f)
    end
end

end # module
