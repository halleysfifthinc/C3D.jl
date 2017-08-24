__precompile__()

module C3D

const LE = 1
const BE = 2

F_ENDIAN = LE
VAX = false

include("vaxtype.jl")

export readc3d

# Parameter format description https://www.c3d.org/HTML/parameterformat1.htm
mutable struct Parameter
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data
    
    # Array format description https://www.c3d.org/HTML/parameterarrays1.htm
    nd::Int8
    dims::Tuple # Vector of bytes (Int8 technically) describing array dimensions
    data::Array
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    
end

Base.show(io::IO, p::Parameter) = show(io, summary(p.data))

# Group format description https://www.c3d.org/HTML/groupformat1.htm
mutable struct Group
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    dl::Int8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    p::Dict{Symbol, Parameter}
end

Base.show(io::IO, g::Group) = show(io, g.p)

relseek(s::IOStream, n::Int) = seek(s, position(s) + n)

function readgroup(f::IOStream)
    pos = position(f)
    nl = saferead(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = saferead(f, Int8)

    name = transcode(String, read(f, abs(nl)))

    if ismatch(r"[^a-zA-Z0-9_ ]",name)
        warn("Group ", name, " has unofficially supported characters. 
            Unexpected results may occur")
    end

    np = saferead(f, Int16)
    dl = saferead(f, Int8)
    desc = transcode(String, read(f, dl))

    return Group(pos, nl, isLocked, gid, name, np, dl, desc, Dict{Symbol, Array{Parameter, 1}}())
end

function readparam(f::IOStream)
    pos = position(f)
    nl = saferead(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = saferead(f, Int8)
    # println(nl)
    name = transcode(String, read(f, abs(nl)))

    if ismatch(r"[^a-zA-Z0-9_ ]",name)
        warn("Parameter ", name, " has unofficially supported characters. 
            Unexpected results may occur")
    end

    np = saferead(f, Int16)

    ellen = saferead(f, Int8)
    if ellen == -1
        T = UInt8
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
        dims = NTuple{convert(Int,nd),Int8}(saferead(f, Int8, nd))
        if T == UInt8
            data = convert.(Char,saferead(f, T, convert.(Int,dims)))
        else
            data = saferead(f, T, convert.(Int,dims))
        end
    else
        dims = ()
        if T == UInt8
            data = [ convert(Char, read(f, T)) ]
        else
            data = [ saferead(f, T) ]
        end
    end

    dl = saferead(f, Int8)
    desc = transcode(String, read(f, dl))

    return Parameter(pos, nl, isLocked, gid, name, np, ellen, nd, dims, data, dl, desc)
end

saferead(f::IOStream, T::Union{Int8, UInt8}) = read(f, T)
saferead(f::IOStream, T::Union{Int8, UInt8}, dims) = read(f, T, dims)

function saferead(f::IOStream, T::Float32)
    if VAX
        if H_ENDIAN === F_ENDIAN
            return read(f, Vax32)::T
        else
            return ltoh(read(f, Vax32))::T
        end
    end

    if H_ENDIAN === F_ENDIAN
        return read(f, T)::T
    elseif F_ENDIAN === LE
        return ltoh(read(f, T))::T
    elseif F_ENDIAN === BE
        return ntoh(read(f, T))::T
    end
end

function saferead(f::IOStream, T::Float32, dims)
    if VAX
        if H_ENDIAN === F_ENDIAN
            return read(f, Vax32, dims)
        else
            return ltoh(read(f, Vax32, dims))
        end
    end

    if H_ENDIAN === F_ENDIAN
        return read(f, T::Float32, dims)
    elseif F_ENDIAN === LE
        return ltoh(read(f, T::Float32, dims))
    elseif F_ENDIAN === BE
        return ntoh(read(f, T::Float32, dims))
    end
end

function saferead(f::IOStream, T)
    if H_ENDIAN === F_ENDIAN
        return read(f, T)::T
    elseif F_ENDIAN === LE
        return ltoh(read(f, T))::T
    elseif F_ENDIAN === BE
        return ntoh(read(f, T))::T
    end
end

function saferead(f::IOStream, T, dims)
    if H_ENDIAN === F_ENDIAN
        return read(f, T, dims)
    elseif F_ENDIAN === LE
        return ltoh(read(f, T, dims))
    elseif F_ENDIAN === BE
        return ntoh(read(f, T, dims))
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

    # Deal with host big-endianness in the future
    if proctype == 1
        # little-endian
        F_ENDIAN = LE
    elseif proctype == 2
        # DEC floats; little-endian
        VAX = true
        F_ENDIAN = LE
        # error("DEC processor type files not supported yet")
    elseif proctype == 3
        # big-endian
        F_ENDIAN = BE
        # error("SGI/MIPS processor type files not supported yet")
    else
        error("Malformed processor type. Expected 1, 2, or 3. Found ", proctype)
    end

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

            local z = read(file, (((params_ptr + paramblocks) - 1) * 512 - 1) - position(file))

            if isempty(find(!iszero,z))
                unmark(file)
                moreparams = false
            else
                reset(file)
                error("Invalid group id at byte ", position(file) + 1)
            end    
        end
    end

    groups = Dict{Symbol, Group}()
    gids = Dict{Int, Symbol}()

    for group in gs
        gname = replace(strip(group.name), r"[^a-zA-Z0-9_ ]", '_')
        groups[Symbol(gname)] = group
        gids[abs(group.gid)] = Symbol(gname)
    end

    for param in ps
        pname = replace(strip(param.name), r"[^a-zA-Z0-9_ ]", '_')
        groups[gids[param.gid]].p[Symbol(pname)] = param
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
