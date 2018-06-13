__precompile__()

module C3D

using VaxData

const LE = 1
const BE = 2

F_ENDIAN = LE
VAX = false

export readc3d, readparams

# Parameter format description https://www.c3d.org/HTML/parameterformat1.htm
struct Parameter{T,N} <: AbstractArray{T,N}
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::String
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data

    # Array format description https://www.c3d.org/HTML/parameterarrays1.htm
    nd::Int8
    dims::Tuple # Vector of bytes (Int8 technically) describing array dimensions
    data::Array{T,N}
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)

end

Base.getindex(p::Parameter, i...) = getindex(p.data, i...)
Base.size(p::Parameter) = size(p.data)

# Group format description https://www.c3d.org/HTML/groupformat1.htm
struct Group
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::String
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    dl::Int8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    p::Dict{Symbol,Parameter}
end

Base.getindex(g::Group, key) = getindex(g.p, key)

Base.show(io::IO, g::Group) = show(io, keys(g.p))

struct C3DFile
    name::String
    header::Dict{Symbol,Any}
    groups::Dict{Symbol,Group}
    d3d::Array
    dad::Array
    bylabels::Dict{Symbol,SubArray}

    function C3DFile(name, header, groups, d3d, dad)
        bylabels = Dict{Symbol,SubArray}()

        for (idx, symname) in enumerate(groups[:POINT][:LABELS][1:groups[:POINT][:USED][1]])
            sym = Symbol(replace(strip(symname), r"[^a-zA-Z0-9_]", '_'))
            bylabels[sym] = view(d3d, :, ((idx-1)*3+1):((idx-1)*3+3))
        end

        for (idx, symname) in enumerate(groups[:ANALOG][:LABELS][1:groups[:ANALOG][:USED][1]])
            sym = Symbol(replace(strip(symname), r"[^a-zA-Z0-9_]", '_'))
            bylabels[sym] = view(dad, :, idx)
        end

        return new(name, header, groups, d3d, dad, bylabels)
    end
end

Base.getindex(f::C3DFile, key) = getindex(f.bylabels, key)

relseek(s::IOStream, n::Int) = seek(s, position(s) + n)

function readheader(f::IOStream)::Dict{Symbol,Any}
    seek(f,0)
    paramptr = saferead(f,Int8)
    read(f,Int8)
    numpoints = saferead(f,Int16)
    numanalog = saferead(f,Int16)
    firstframe = saferead(f,Int16)
    lastframe = saferead(f,Int16)
    maxinterp = saferead(f,Int16)
    pointscale = saferead(f,Float32)
    DATA_START = saferead(f,Int16)
    analogpframe = saferead(f,Int16)
    framerate = saferead(f,Float32)
    seek(f, (148 - 1) * 2)
    tmp = saferead(f, Int16)
    tmp_lr = saferead(f, Int16)
    lr = (tmp == 0x3039) ? tmp_lr : nothing
    char4 = (saferead(f, Int16) == 0x3039)
    numevents = saferead(f, Int16)
    read(f,Int16)
    eventtimes = saferead(f, Float32, 18)
    eventflags = BitArray(saferead(f, Int8, 18))
    read(f,Int16)

    tdata = convert.(Char, saferead(f, UInt8, (4, 18)))
    eventlabels = [ String(tdata[((i - 1) * 4 + 1):(i * 4)]) for i in 1:18]

    (length(find(eventflags)) != numevents) && 1 # They should be the same, header is not authoritative tho, so don't error?
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

function readgroup(f::IOStream)
    pos = position(f)
    nl = saferead(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = saferead(f, Int8)

    name = transcode(String, read(f, abs(nl)))
    symname = replace(strip(name), r"[^a-zA-Z0-9_]", '_')

    if ismatch(r"[^a-zA-Z0-9_ ]", name)
        warn("Group ", name, " has unofficially supported characters. 
            Unexpected results may occur")
    end

    np = saferead(f, Int16)
    dl = saferead(f, Int8)
    desc = transcode(String, read(f, dl))

    return Group(pos, nl, isLocked, gid, name, symname, np, dl, desc, Dict{Symbol,Array{Parameter,1}}())
end

function readparam(f::IOStream)
    pos = position(f)
    nl = saferead(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = saferead(f, Int8)
    # println(nl)
    name = transcode(String, read(f, abs(nl)))
    symname = replace(strip(name), r"[^a-zA-Z0-9_]", '_')

    if ismatch(r"[^a-zA-Z0-9_ ]", name)
        warn("Parameter ", name, " has unofficially supported characters.
            Unexpected results may occur")
    end

    np = saferead(f, Int16)

    ellen = saferead(f, Int8)
    if ellen == -1
        T = String
    elseif ellen == 1
        T = Int8
    elseif ellen == 2
        T = Int16
    elseif ellen == 4
        T = Float32
    else
        println("File position in bytes ", position(f))
        println("nl: ", nl, "\ngid: ", gid, "\nname: ", name, "\nnp: ", np, "\nellen: ", ellen)
        error("Invalid parameter element type. Found ", ellen)
    end

    nd = saferead(f, Int8)
    if nd > 0
        dims = NTuple{convert(Int, nd),Int8}(saferead(f, Int8, nd))
        if T == String
            tdata = convert.(Char, saferead(f, UInt8, convert.(Int, dims)))
            if nd > 1
                data = [ String(tdata[((i - 1) * dims[1] + 1):(i * dims[1])]) for i in 1:(*)(dims[2:end]...)]
            else
                data = [ String(tdata) ]
            end
        else
            data = saferead(f, T, convert.(Int, dims))
        end
    else
        dims = ()
        if T == String
            data = [ convert(Char, read(f, UInt8)) ]
        else
            data = [ saferead(f, T) ]
        end
    end

    dl = saferead(f, Int8)
    desc = transcode(String, read(f, dl))

    N = nd == 0 ? 1 : convert(Int,nd)

    if T == String && N > 1
        N -= 1
    end

    return Parameter{T,N}(pos, nl, isLocked, gid, name, symname, np, ellen, nd, dims, data,
            dl, desc)
end

function readdata(f::IOStream, groups::Dict{Symbol,Group}, header)

    format = groups[:POINT][:SCALE][1] > 0 ? Int16 : Float32

    # Read data in a transposed structure for better read/write speeds due to Julia being
    # column-order arrays
    d3rows::Int = groups[:POINT][:USED][1]*3
    d3cols::Int = (groups[:POINT][:FRAMES][1] < 0) ? convert(Int,reinterpret(UInt16, groups[:POINT][:FRAMES][1])) : groups[:POINT][:FRAMES][1]
    d3d = Array{Float32,2}(undef, d3rows,d3cols)
    d3residuals = Array{Float32,2}(undef, convert(Int,d3rows/3),d3cols)

    apf::Int = groups[:ANALOG][:RATE][1]/groups[:POINT][:RATE][1]
    darows::Int = groups[:ANALOG][:USED][1]
    dacols::Int = apf*d3cols
    dad = Array{Float32,2}(undef, darows,dacols)

    for i in 1:d3cols
        tmp = saferead(f,format,convert(Int,d3rows*4/3))
        d3d[:,i] = tmp[filter(x -> x % 4 != 0, 1:convert(Int,d3rows*4/3))]
        d3residuals[:,i] = tmp[filter(x -> x % 4 == 0, 1:convert(Int,d3rows*4/3))]
        dad[:,((i-1)*apf+1):(i*apf)] = saferead(f,format,(darows,apf))
    end

    if format == Int16
        # Multiply or divide by [:point][:scale]
        d3d *= abs(groups[:POINT][:SCALE][1])
    end

    dad[:] = (dad - groups[:ANALOG][:OFFSET][1])*
                groups[:ANALOG][:GEN_SCALE][1].*
                groups[:ANALOG][:SCALE][1:length(groups[:ANALOG][:USED])]

    return C3DFile(f.name, header, groups, d3d', dad')
end

saferead(f::IOStream, T::Union{Type{Int8},Type{UInt8}}) = read(f, T)
saferead(f::IOStream, T::Union{Type{Int8},Type{UInt8}}, dims) = read!(f, Array{T}(undef, dims...))

function saferead(f::IOStream, T::Type{Float32})
    if VAX
        if H_ENDIAN === F_ENDIAN
            return convert(Float32,read(f, VaxFloatF))
        else
            return convert(Float32,ltoh(read(f, VaxFloatF)))
        end
    end

    if H_ENDIAN === F_ENDIAN
        return read(f, T)
    elseif F_ENDIAN === LE
        return ltoh(read(f, T))
    elseif F_ENDIAN === BE
        return ntoh(read(f, T))
    end
end

function saferead(f::IOStream, T::Type{Float32}, dims)
    if VAX
        if H_ENDIAN === F_ENDIAN
            return convert.(Float32,read!(f, Array{VaxFloatF}(undef, dims...)))
        else
            return convert.(Float32,ltoh.(read!(f, Array{VaxFloatF}(undef, dims...))))
        end
    end

    if H_ENDIAN === F_ENDIAN
        return read!(f, Array{T}(undef, dims))
    elseif F_ENDIAN === LE
        return ltoh.(read!(f, Array{T}(undef, dims)))
    elseif F_ENDIAN === BE
        return ntoh.(read!(f, Array{T}(undef, dims)))
    end
end

function saferead(f::IOStream, T::Type)
    if H_ENDIAN === F_ENDIAN
        return read(f, T)
    elseif F_ENDIAN === LE
        return ltoh(read(f, T))
    elseif F_ENDIAN === BE
        return ntoh(read(f, T))
    end
end

function saferead(f::IOStream, T::Type, dims)
    if H_ENDIAN === F_ENDIAN
        return read!(f, Array{T}(undef, dims...))
    elseif F_ENDIAN === LE
        return ltoh.(read!(f, Array{T}(undef, dims...)))
    elseif F_ENDIAN === BE
        return ntoh.(read!(f, Array{T}(undef, dims...)))
    end
end

function readc3d(filename::AbstractString)
    if !isfile(filename)
        error("File ", filename, " cannot be found")
    end

    file = open(filename, "r")

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

    global VAX = false

    # Deal with host big-endianness in the future
    if proctype == 1
        # little-endian
        global F_ENDIAN = LE
    elseif proctype == 2
        # DEC floats; little-endian
        global VAX = true
        global F_ENDIAN = LE
    elseif proctype == 3
        # big-endian
        global F_ENDIAN = BE
    else
        error("Malformed processor type. Expected 1, 2, or 3. Found ", proctype)
    end

    mark(file)
    header = readheader(file)
    reset(file)

    gs = Array{Group,1}()
    ps = Array{Parameter,1}()
    moreparams = true

    read(file, UInt8)
    if read(file, Int8) < 0
        # Group
        relseek(file, -2)
        push!(gs, readgroup(file))
        moreparams = gs[end].np != 0 ? true : false
    else
        # Parameter
        relseek(file, -2)
        push!(ps, readparam(file))
        moreparams = ps[end].np != 0 ? true : false
    end

    while moreparams
        read(file, UInt8)
        local gid = read(file, Int8)
        if gid < 0 # Group
            relseek(file, -2)
            push!(gs, readgroup(file))
            moreparams = gs[end].np != 0 ? true : false
        elseif gid > 0 # Parameter
            relseek(file, -2)
            push!(ps, readparam(file))
            moreparams = ps[end].np != 0 ? true : false
        else # Last parameter pointer is incorrect (assumption)
            # The group ID should never be zero, if it is, the most likely explanation is
            # that the pointer is incorrect (ie the end of the parameters has been reached
            # and the remaining 0x00's are fill to the end of the block

            # Check if pointer is incorrect
            relseek(file, -2)
            mark(file)

            local z = read(file, (((params_ptr + paramblocks) - 1) * 512) - position(file))

            if isempty(find(!iszero, z))
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
        groups[Symbol(group.symname)] = group
        gids[abs(group.gid)] = Symbol(group.symname)
    end

    for param in ps
        groups[gids[param.gid]].p[Symbol(param.symname)] = param
    end

    res = readdata(file,groups, header)

    close(file)

    return res
end

function readparams(filename::AbstractString)
    if !isfile(filename)
        error("File ", filename, " cannot be found")
    end

    file = open(filename, "r")

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

    global VAX = false

    # Deal with host big-endianness in the future
    if proctype == 1
        # little-endian
        global F_ENDIAN = LE
    elseif proctype == 2
        # DEC floats; little-endian
        global VAX = true
        global F_ENDIAN = LE
    elseif proctype == 3
        # big-endian
        global F_ENDIAN = BE
    else
        error("Malformed processor type. Expected 1, 2, or 3. Found ", proctype)
    end

    mark(file)
    header = readheader(file)
    reset(file)

    gs = Array{Group,1}()
    ps = Array{Parameter,1}()
    moreparams = true

    read(file, UInt8)
    if read(file, Int8) < 0
        # Group
        relseek(file, -2)
        push!(gs, readgroup(file))
        moreparams = gs[end].np != 0 ? true : false
    else
        # Parameter
        relseek(file, -2)
        push!(ps, readparam(file))
        moreparams = ps[end].np != 0 ? true : false
    end

    while moreparams
        read(file, UInt8)
        local gid = read(file, Int8)
        if gid < 0 # Group
            relseek(file, -2)
            push!(gs, readgroup(file))
            moreparams = gs[end].np != 0 ? true : false
        elseif gid > 0 # Parameter
            relseek(file, -2)
            push!(ps, readparam(file))
            moreparams = ps[end].np != 0 ? true : false
        else # Last parameter pointer is incorrect (assumption)
            # The group ID should never be zero, if it is, the most likely explanation is
            # that the pointer is incorrect (ie the end of the parameters has been reached
            # and the remaining 0x00's are fill to the end of the block

            # Check if pointer is incorrect
            relseek(file, -2)
            mark(file)

            local z = read(file, (((params_ptr + paramblocks) - 1) * 512) - position(file))

            if isempty(find(!iszero, z))
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
        groups[Symbol(group.symname)] = group
        gids[abs(group.gid)] = Symbol(group.symname)
    end

    for param in ps
        groups[gids[param.gid]].p[Symbol(param.symname)] = param
    end

    close(file)

    return groups
end

function __init__()
    if ENDIAN_BOM == 0x04030201
        global const H_ENDIAN = LE
    elseif ENDIAN_BOM == 0x01020304
        global const H_ENDIAN = BE
    else
        error("Weird endianness error")
    end
end

end # module
