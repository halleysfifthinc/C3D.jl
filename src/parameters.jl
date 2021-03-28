abstract type AbstractParameter{T,N} end

struct ParameterTypeError <: Exception
    found::Int
    position::Int
end

struct Parameter{P<:AbstractParameter}
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    payload::P
end

# Parameter format description https://www.c3d.org/HTML/parameterformat1.htm
struct ArrayParameter{T,N} <: AbstractParameter{T,N}
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data

    # Array format description https://www.c3d.org/HTML/parameterarrays1.htm
    nd::UInt8
    dims::NTuple{N,Int} # Vector of bytes (Int8 technically) describing array dimensions
    data::Array{T,N}
end

struct StringParameter <: AbstractParameter{String,1}
    data::Array{String,1}
end

struct ScalarParameter{T} <: AbstractParameter{T,0}
    data::T
end

function Base.unsigned(p::Parameter{<:AbstractParameter{T}}) where {T <: Number}
    return Parameter(p.pos, p.nl, p.isLocked, p.gid, p.name, p.symname,
        p.np, p.dl, p.desc, unsigned(p.payload))
end

function Base.unsigned(p::ArrayParameter{T,N}) where {T,N}
    uT = unsigned(T)
    return ArrayParameter{uT,N}(p.ellen, p.nd, p.dims, unsigned.(p.data))
end

function Base.unsigned(p::ScalarParameter{T}) where T
    uT = unsigned(T)
    return ScalarParameter{uT}(unsigned(p.data))
end

function Parameter{StringParameter}(p::Parameter{ScalarParameter{String}})
    return Parameter{StringParameter}(p.pos, p.nl, p.isLocked, p.gid, p.name, p.symname,
        p.np, p.dl, p.desc, StringParameter([x.data]))
end

function Base.getproperty(param::Parameter{P}, name::Symbol) where P <: AbstractParameter
    if name === :pos
        return getfield(param, :pos)::Int
    elseif name === :nl
        return getfield(param, :nl)::Int8
    elseif name === :isLocked
        return getfield(param, :isLocked)::Bool
    elseif name === :gid
        return getfield(param, :gid)::Int8
    elseif name === :name
        return getfield(param, :name)::String
    elseif name === :symname
        return getfield(param, :symname)::Symbol
    elseif name === :np
        return getfield(param, :np)::Int16
    elseif name === :dl
        return getfield(param, :dl)::UInt8
    elseif name === :desc
        return getfield(param, :desc)::String
    elseif name === :payload
        return getfield(param, :payload)::P
    end
end

function readparam(io::IOStream, FEND::Endian, FType::Type{Y}) where Y <: Union{Float32,VaxFloatF}
    pos = position(io)
    nl = read(io, Int8)
    @assert nl != 0
    isLocked = nl < 0 ? true : false
    gid = read(io, Int8)
    @assert gid != 0
    name = transcode(String, read(io, abs(nl)))
    @assert any(!iscntrl, name)
    symname = Symbol(replace(strip(name), r"[^a-zA-Z0-9_]" => '_'))

    # if occursin(r"[^a-zA-Z0-9_ ]", name)
    #     @debug "Parameter $name at $pos has unofficially supported characters.
    #         Unexpected results may occur"
    # end

    np = saferead(io, Int16, FEND)

    ellen = read(io, Int8)
    if ellen == -1
        T = String
    elseif ellen == 1
        T = Int8
    elseif ellen == 2
        T = Int16
    elseif ellen == 4
        T = FType
    else
        throw(ParameterTypeError(ellen, position(io)))
    end

    nd = read(io, UInt8)
    if nd > 0
        dims = NTuple{convert(Int, nd),Int}(read!(io, Array{UInt8}(undef, nd)))
        data = _readarrayparameter(io, FEND, T, dims)
    else
        data = _readscalarparameter(io, FEND, T)
    end

    dl = read(io, UInt8)
    desc = transcode(String, read(io, dl))

    if any(iscntrl, desc)
        desc = ""
    end

    pointer = pos + np + abs(nl) + 2
    # if position(io) != pointer
    #     @debug "wrong pointer in $name" position(io) pointer
    # end

    if data isa AbstractArray
        if all(size(data) .< 2) && !isempty(data)
            # In the event of an 'array' parameter with only one element
            payload = ScalarParameter(data[1])
        elseif eltype(data) === String
            payload = StringParameter(data)
        else
            payload = ArrayParameter(ellen, nd, dims, data)
        end
    else
        payload = ScalarParameter(data)
    end

    return Parameter(pos, nl, isLocked, gid, name, symname, np, dl, desc, payload)
end

function _readscalarparameter(io::IO, FEND::Endian, ::Type{T}) where T
    return saferead(io, T, FEND)
end

function _readscalarparameter(io::IO, FEND::Endian, ::Type{String})::String
    return rstrip(x -> iscntrl(x) || isspace(x), transcode(String, read(io, UInt8)))
end

function _readarrayparameter(io::IO, FEND::Endian, ::Type{T}, dims) where T
    return saferead(io, T, FEND, dims)
end

function _readarrayparameter(io::IO, FEND::Endian, ::Type{String}, dims)::Array{String}
    tdata = convert.(Char, read!(io, Array{UInt8}(undef, dims)))
    if length(dims) > 1
        data = [ rstrip(x -> iscntrl(x) || isspace(x),
                        String(@view(tdata[((i - 1) * dims[1] + 1):(i * dims[1])]))) for i in 1:(*)(dims[2:end]...)]
    else
        data = [ rstrip(String(tdata)) ]
    end
    return data
end
