abstract type AbstractParameter{T,N} end

struct ParameterTypeError <: Exception
    found::Int
    position::Int
end

# Parameter format description https://www.c3d.org/HTML/Documents/parameterformat1.htm
struct Parameter{P<:AbstractParameter}
    pos::Int
    gid::Int8 # Group ID
    locked::Bool # Locked if nl < 0
    _name::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    name::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    _desc::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    payload::P
end

# Array format description https://www.c3d.org/HTML/Documents/parameterarrays1.htm
struct ArrayParameter{T,N} <: AbstractParameter{T,N}
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data

    nd::UInt8
    dims::NTuple{N,Int} # Vector of bytes (Int8 technically) describing array dimensions
    data::Array{T,N}
end

struct StringParameter <: AbstractParameter{String,1}
    data::Array{String,1}
end

function StringParameter(s::String)
    return StringParameter([s])
end

mutable struct ScalarParameter{T} <: AbstractParameter{T,0}
    data::T
end

function Parameter(pos, gid, lock, name, np, desc, payload)
    return Parameter(pos, convert(Int8, gid), lock, Vector{UInt8}(name), Symbol(name),
        convert(Int16, np), Vector{UInt8}(desc), payload)
end

function Parameter(name, desc, payload::P; gid=0, locked=signbit(gid)) where {P<:Union{Vector{String},String}}
    return Parameter(0, gid, locked, name, 0, desc, StringParameter(payload))
end

function Parameter(name, desc, payload::AbstractArray{T,N}; gid=0, locked=signbit(gid)) where {T<:Union{Int8,Int16,Float32},N}
    return Parameter(0, gid, locked, name, 0, desc,
        ArrayParameter{T,N}(sizeof(T), ndims(payload), size(payload), payload))
end

function Parameter(name, desc, payload::T; gid=0, locked=signbit(gid)) where {T}
    return Parameter(0, gid, locked, name, 0, desc, ScalarParameter{T}(payload))
end

function Parameter{StringParameter}(p::Parameter{ScalarParameter{String}})
    return Parameter{StringParameter}(p.pos, p.gid, p.locked, p._name, p.name,
        p.np, p._desc, StringParameter(p.payload.data))
end

function Base.unsigned(p::Parameter{<:AbstractParameter{T}}) where {T <: Number}
    return Parameter(p.pos, p.gid, p.locked, p._name, p.name, p.np, p._desc, unsigned(p.payload))
end

function Base.unsigned(p::ArrayParameter{T,N}) where {T,N}
    uT = unsigned(T)
    return ArrayParameter{uT,N}(p.ellen, p.nd, p.dims, unsigned.(p.data))
end

function Base.unsigned(p::ScalarParameter{T}) where T
    uT = unsigned(T)
    return ScalarParameter{uT}(unsigned(p.data))
end

function readparam(io::IOStream, ::Type{END}) where {END<:AbstractEndian}
    pos = position(io)
    nl = read(io, Int8)
    @assert nl != 0
    locked = signbit(nl)
    gid = read(io, Int8)
    @assert gid != 0
    _name = read(io, abs(nl))
    @assert any(!iscntrl∘Char, _name)
    name = Symbol(replace(strip(transcode(String, copy(_name))), r"[^a-zA-Z0-9_]" => '_'))

    @debug "Parameter $name at $pos has unofficially supported characters.
        Unexpected results may occur" maxlog=occursin(r"[^a-zA-Z0-9_ ]", name)

    np = read(io, END(Int16))

    ellen = read(io, Int8)
    if ellen == -1
        T = String
    elseif ellen == 1
        T = Int8
    elseif ellen == 2
        T = Int16
    elseif ellen == 4
        T = eltype(END)
    else
        throw(ParameterTypeError(ellen, position(io)))
    end

    nd = read(io, UInt8)
    if nd > 0
        # dims = (read!(io, Array{UInt8}(undef, nd))...)
        dims = NTuple{convert(Int, nd),Int}(read!(io, Array{UInt8}(undef, nd)))
        data = _readarrayparameter(io, END(T), dims)
    else
        data = _readscalarparameter(io, END(T))
    end

    dl = read(io, UInt8)
    desc = read(io, dl)

    if any(iscntrl∘Char, desc)
        desc = ""
    end

    pointer = pos + np + abs(nl) + 2
    @debug "wrong pointer in $name" position(io) pointer maxlog=(position(io) != pointer)

    if data isa AbstractArray
        if all(<(2), size(data)) && !isempty(data)
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

    return Parameter(pos, gid, locked, _name, name, np, desc, payload)
end

function _readscalarparameter(io::IO, ::Type{END}) where {END<:AbstractEndian}
    return read(io, END)
end

function _readscalarparameter(io::IO, ::Type{<:AbstractEndian{String}})::String
    return rstrip(x -> iscntrl(x) || isspace(x), transcode(String, read(io, UInt8)))
end

function _readarrayparameter(io::IO, ::Type{END}, dims) where {END<:AbstractEndian}
    T = eltype(END) <: VaxFloat ? Float32 : eltype(END)
    a = Array{T}(undef, dims)
    return read!(io, a, END)
end

function _readarrayparameter(io::IO, ::Type{<:AbstractEndian{String}}, dims)::Array{String}
    tdata = convert.(Char, read!(io, Array{UInt8}(undef, dims)))
    if length(dims) > 1
        data = [ rstrip(x -> iscntrl(x) || isspace(x),
                        String(@view(tdata[((i - 1) * dims[1] + 1):(i * dims[1])]))) for i in 1:(*)(dims[2:end]...)]
    else
        data = [ rstrip(String(tdata)) ]
    end
    return data
end
