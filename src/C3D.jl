__precompile__()

module C3D

using VaxData

@enum Endian LE=1 BE=2

export readc3d, readparams

include("parameters.jl")
include("groups.jl")

struct C3DFile
    name::String
    # header::Dict{Symbol,Any}
    groups::Dict{Symbol,Group}
    point::Dict{String,Array{Float32,2}}
    analog::Dict{String,Array{Float32,1}}
end

function C3DFile(name::String, groups::Dict{Symbol,Group}, point::AbstractArray, analog::AbstractArray)
    fpoint = Dict{String,Array{Float32,2}}()
    fanalog = Dict{String,Array{Float32,1}}()

    # fill fpoint with 3d point data
    for (idx, symname) in enumerate(groups[:POINT][:LABELS][1:groups[:POINT][:USED][1]])
        fpoint[symname] = point[:,((idx-1)*3+1):((idx-1)*3+3)]
    end

    for (idx, symname) in enumerate(groups[:ANALOG][:LABELS][1:groups[:ANALOG][:USED][1]])
        fanalog[symname] = analog[:, idx]
    end

    return C3DFile(name, groups, fpoint, fanalog)
end

function Base.show(io::IO, f::C3DFile)
    length = (f.groups[:POINT][:FRAMES][1] == typemax(UInt16)) ?
        f.groups[:POINT][:LONG_FRAMES][1]/f.groups[:POINT][:RATE][1] :
        f.groups[:POINT][:FRAMES][1]/f.groups[:POINT][:RATE][1]

    if get(io, :compact, true)
        print(io, "C3DFile(\"", f.name, "\")")
    else
        print(io, "C3DFile(\"", f.name, "\", ",
              length, "sec, ",
              f.groups[:POINT][:USED][1], " points, ",
              f.groups[:ANALOG][:USED][1], " analog channels)")
    end
end

function readheader(f::IOStream, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    seek(f,0)
    paramptr = read(f, Int8)
    read(f, Int8)
    numpoints = saferead(f, Int16, FEND)
    numanalog = saferead(f, Int16, FEND)
    firstframe = saferead(f, Int16, FEND)
    lastframe = saferead(f, Int16, FEND)
    maxinterp = saferead(f, Int16, FEND)
    pointscale = saferead(f, FType, FEND)
    DATA_START = saferead(f, Int16, FEND)
    analogpframe = saferead(f, Int16, FEND)
    framerate = saferead(f, FType, FEND)
    seek(f, (148 - 1) * 2)
    tmp = saferead(f, Int16, FEND)
    tmp_lr = saferead(f, Int16, FEND)
    lr = (tmp == 0x3039) ? tmp_lr : nothing
    char4 = (saferead(f, Int16, FEND) == 0x3039)
    numevents = saferead(f, Int16, FEND)
    read(f, Int16)
    eventtimes = saferead(f, FType, FEND, 18)
    eventflags = BitArray(read(f, Int8, 18))
    read(f, Int16)

    tdata = convert.(Char, read(f, UInt8, (4, 18)))
    eventlabels = [ String(tdata[((i - 1) * 4 + 1):(i * 4)]) for i in 1:18]

    (length(findall(eventflags)) != numevents) && 1 # They should be the same, header is not authoritative tho, so don't error?
    eventtimes = eventtimes[eventflags]
    eventlabels = eventlabels[eventflags]

    return Dict(:paramptr => paramptr,
                :numpoints => numpoints,
                :numanalog => numanalog,
                :firstframe => firstframe,
                :lastframe => lastframe,
                :maxinterp => maxinterp,
                :pointscale => pointscale,
                :DATA_START => DATA_START,
                :analogpframe => analogpframe,
                :framerate => framerate,
                :lr => lr,
                :numevents => numevents,
                :eventtimes => eventtimes,
                :eventflags => eventflags,
                :eventlabels => eventlabels)
end

function readdata(f::IOStream, groups::Dict{Symbol,Group}, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    format = groups[:POINT][:SCALE][1] > 0 ? Int16 : FType

    # Read data in a transposed structure for better read/write speeds due to Julia being
    # column-order arrays
    nummarkers = convert(Int, groups[:POINT][:USED][1])
    numframes = convert(Int, groups[:POINT][:FRAMES][1])
    point = Array{Float32,2}(undef, nummarkers*3, numframes)
    # residuals = Array{Float32,2}(undef, nummarkers, numframes)

    # Analog Samples Per Frame => ASPF
    aspf = convert(Int, groups[:ANALOG][:RATE][1]/groups[:POINT][:RATE][1])
    numchannels = convert(Int, groups[:ANALOG][:USED][1])
    analog = Array{Float32,2}(undef, numchannels, aspf*numframes)

    nb = nummarkers*4
    pointidxs = filter(x -> x % 4 != 0, 1:nb)
    # residxs = filter(x -> x % 4 == 0, 1:nb)

    pointtmp = Array{format}(undef, nb)
    analogtmp = Array{format}(undef, (numchannels,aspf))
    pointview = @view(pointtmp[pointidxs])

    for i in 1:numframes
        saferead!(f, pointtmp, FEND)
        point[:,i] = convert.(Float32, pointview) # Convert from `format` (eg Int16 or FType)
        # residuals[:,i] = tmp[residxs]
        saferead!(f, analogtmp, FEND)
        analog[:,((i-1)*aspf+1):(i*aspf)] = convert.(Float32, analogtmp)
    end

    if format == Int16
        # Multiply or divide by [:point][:scale]
        point .*= abs(groups[:POINT][:SCALE][1])
    end

    analog[:] = (analog .- groups[:ANALOG][:OFFSET][1]).*
                groups[:ANALOG][:GEN_SCALE][1].*
                groups[:ANALOG][:SCALE][1:length(groups[:ANALOG][:USED])]

    # return C3DFile(f.name, groups, permutedims(point), permutedims(analog))
    return (permutedims(point), permutedims(analog))
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

function saferead(io::IOStream, ::Type{T}, FEND::Endian, dims) where T
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

function saferead(io::IOStream, ::Type{VaxFloatF}, FEND::Endian, dims)
    if FEND == LE
        return convert.(Float32, ltoh.(read!(io, Array{VaxFloatF}(undef, dims))))
    else
        return convert.(Float32, ntoh.(read!(io, Array{VaxFloatF}(undef, dims))))
    end
end

function readc3d(filename::AbstractString)
    if !isfile(filename)
        error("File ", filename, " cannot be found")
    end

    file = open(filename, "r")

    groups, FEND, FType = _readparams(file)

    (point, analog) = readdata(file, groups, FEND, FType)

    res = C3DFile(filename, groups, point, analog)

    close(file)

    return res
end

function _readparams(file::IOStream)
    params_ptr = read(file, UInt8)

    if read(file, UInt8) != 0x50
        error("File ", filename, " is not a valid C3D file")
    end

    # Jump to parameters block
    seek(file, (params_ptr - 1) * 512)

    # Skip 2 reserved bytes
    # TODO: store bytes for saving modified files
    read(file, UInt16)

    paramblocks = read(file, UInt8)
    proctype = read(file, Int8) - 83

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

    mark(file)
    # header = readheader(file, FEND, FType)
    reset(file)

    gs = Array{Group,1}()
    ps = Array{Parameter,1}()
    moreparams = true

    read(file, UInt8)
    if read(file, Int8) < 0
        # Group
        skip(file, -2)
        push!(gs, readgroup(file, FEND, FType))
        moreparams = gs[end].np != 0 ? true : false
    else
        # Parameter
        skip(file, -2)
        push!(ps, readparam(file, FEND, FType))
        moreparams = ps[end].np != 0 ? true : false
    end

    while moreparams
        read(file, UInt8)
        local gid = read(file, Int8)
        if gid < 0 # Group
            skip(file, -2)
            push!(gs, readgroup(file, FEND, FType))
            moreparams = gs[end].np != 0 ? true : false
        elseif gid > 0 # Parameter
            skip(file, -2)
            push!(ps, readparam(file, FEND, FType))
            moreparams = ps[end].np != 0 ? true : false
        else # Last parameter pointer is incorrect (assumption)
            # The group ID should never be zero, if it is, the most likely explanation is
            # that the pointer is incorrect (ie the end of the parameters has been reached
            # and the remaining 0x00's are fill to the end of the block

            # Check if pointer is incorrect
            skip(file, -2)
            mark(file)

            local z = read(file, (((params_ptr + paramblocks) - 1) * 512) - position(file))

            if isempty(findall(!iszero, z))
                unmark(file)
                moreparams = false
            else
                reset(file)
                error("Invalid group id at byte ", position(file) + 1)
            end
        end
    end

    groups = Dict{Symbol,Group}()
    gids = Dict{Int,Symbol}()

    for group in gs
        groups[group.symname] = group
        gids[abs(group.gid)] = group.symname
    end

    for param in ps
        groups[gids[param.gid]].p[param.symname] = param
    end

    return (groups, FEND, FType)
end

function readparams(filename::AbstractString)
    if !isfile(filename)
        error("File ", filename, " cannot be found")
    end

    file = open(filename, "r")

    groups, header, FEND, FType = _readparams(file)

    close(file)

    return groups
end

end # module
