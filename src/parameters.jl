abstract type AbstractParameter end

# Parameter format description https://www.c3d.org/HTML/parameterformat1.htm
struct ArrayParameter{T,N} <: AbstractParameter
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data

    # Array format description https://www.c3d.org/HTML/parameterarrays1.htm
    nd::Int8
    dims::NTuple{N,Int} # Vector of bytes (Int8 technically) describing array dimensions
    data::Array{T,N}
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
end

struct StringParameter <: AbstractParameter
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    data::Array{String,1}
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
end

struct ScalarParameter{T} <: AbstractParameter
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    data::T
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
end

function readparam(f::IOStream, FEND::Endian, FType::Type{Y}) where Y <: Union{Float32,VaxFloatF}
    pos = position(f)
    nl = read(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = read(f, Int8)
    name = transcode(String, read(f, abs(nl)))
    symname = Symbol(replace(strip(name), r"[^a-zA-Z0-9_]" => '_'))

    if occursin(r"[^a-zA-Z0-9_ ]", name)
        warn("Parameter ", name, " has unofficially supported characters.
            Unexpected results may occur")
    end

    np = saferead(f, Int16, FEND)

    ellen = read(f, Int8)
    if ellen == -1
        T = String
    elseif ellen == 1
        T = Int8
    elseif ellen == 2
        T = Int16
    elseif ellen == 4
        T = FType
    else
        println("File position in bytes ", position(f))
        println("nl: ", nl, "\ngid: ", gid, "\nname: ", name, "\nnp: ", np, "\nellen: ", ellen)
        error("Invalid parameter element type. Found ", ellen)
    end

    nd = read(f, UInt8)
    if nd > 0
        dims = NTuple{convert(Int, nd),Int}(read!(f, Array{UInt8}(undef, nd)))
        data = _readarrayparameter(f, FEND, T, dims)
    else
        data = _readscalarparameter(f, FEND, T)
    end

    dl = read(f, UInt8)
    desc = transcode(String, read(f, dl))

    if data isa AbstractArray
        if eltype(data) === String
            return StringParameter(pos, nl, isLocked, gid, name, symname, np, data, dl, desc)
        else
            return ArrayParameter(pos, nl, isLocked, gid, name, symname, np, ellen, nd, dims, data, dl, desc)
        end
    else
        return ScalarParameter(pos, nl, isLocked, gid, name, symname, np, data, dl, desc)
    end
end

function _readscalarparameter(f::IO, FEND::Endian, ::Type{T}) where T
    return saferead(f, T, FEND)
end

function _readscalarparameter(f::IO, FEND::Endian, ::Type{String})::String
    return transcode(String, read(f, UInt8))
end

function _readarrayparameter(f::IO, FEND::Endian, ::Type{T}, dims) where T
    return saferead(f, T, FEND, dims)
end

function _readarrayparameter(f::IO, FEND::Endian, ::Type{String}, dims)::Array{String}
    tdata = convert.(Char, read!(f, Array{UInt8}(undef, dims)))
    if length(dims) > 1
       data = [ String(@view(tdata[((i - 1) * dims[1] + 1):(i * dims[1])])) for i in 1:(*)(dims[2:end]...)]
    else
       data = [ String(tdata) ]
    end
    return data
end

