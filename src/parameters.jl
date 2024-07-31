abstract type AbstractParameter{T,N} end

struct ParameterTypeError <: Exception
    msg::String
end

function Base.showerror(io::IO, e::ParameterTypeError)
    print(io, e.msg)
end

# Parameter format description https://www.c3d.org/HTML/Documents/parameterformat1.htm
mutable struct Parameter{P<:AbstractParameter}
    const pos::Int
    gid::Int8 # Group ID
    const locked::Bool # Locked if nl < 0
    const _name::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    const name::Symbol
    const np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    const _desc::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    const payload::P
end

# Array format description https://www.c3d.org/HTML/Documents/parameterarrays1.htm
struct ArrayParameter{T,N} <: AbstractParameter{T,N}
    elsize::Int8
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
    return ArrayParameter{uT,N}(p.elsize, p.nd, p.dims, unsigned.(p.data))
end

function Base.unsigned(p::ScalarParameter{T}) where T
    uT = unsigned(T)
    return ScalarParameter{uT}(unsigned(p.data))
end

function Base.show(io::IO, p::Parameter{P}) where P
    print(io, ":$(p.name)")

    elsize = _elsize(p)
    elt = elsize == -1 ? String :
          elsize == 1  ? UInt8 :
          elsize == 2 ? UInt16 : Float32

    printstyled(io, "::$elt "; color=:light_black)
    if elt <: String
        if _ndims(p) > 1
            printstyled(io, "@ $(_size(p)[2:end]) "; bold=true, color=:light_black)
        end
    elseif _ndims(p) > 1
        printstyled(io, "@ $(_size(p)) "; bold=true, color=:light_black)
    end

    # TODO: Print numbers in REPL number literal colors
    if elt <: String && _ndims(p) == 1
        print(io, repr(p.payload.data))
    else
        print(io, p.payload.data)
    end
end

function Base.show(io::IO, ::MIME"text/plain", p::Parameter{P}) where P
    print(io, "Parameter(:$(p.name)")
    if !isempty(p._desc)
        print(io, ", ")
        printstyled(io, "\"", transcode(String, copy(p._desc)), "\""; color=:light_black)
    end
    print(io, ")")
    elsize = _elsize(p)
    elt = elsize == -1 ? String :
          elsize == 1  ? UInt8 :
          elsize == 2 ? UInt16 : Float32

    printstyled(io, "::$elt "; color=:light_black)
    if elt <: String
        if _ndims(p) > 1
            printstyled(io, "@ $(_size(p)[2:end]) "; bold=true, color=:light_black)
        end
    elseif _ndims(p) > 1
        printstyled(io, "@ $(_size(p)) "; bold=true, color=:light_black)
    end


    print(io, "\n  ", p.payload.data)
end

function _elsize(::Parameter{P}) where P <: Union{StringParameter,ScalarParameter{String}}
    return -1
end

function _elsize(::Parameter{<:Union{ArrayParameter{T},ScalarParameter{T}}}) where T
    return sizeof(T)
end

function _ndims(p::Parameter{StringParameter})
    return length(p.payload.data) > 1 ? 2 : 1
end

_ndims(p::Parameter{ScalarParameter{String}}) = 1

function _ndims(p::Parameter{ScalarParameter{T}}) where T
    return 0
end

function _ndims(p::Parameter{ArrayParameter{T,N}}) where {T,N}
    return ndims(p.payload.data)
end

function _size(p::Parameter{StringParameter})
    return length(p.payload.data) > 1 ? (maximum(length, p.payload.data), length(p.payload.data)) : (isempty(p.payload.data) ? 0 : length(only(p.payload.data)),)
end

function _size(p::Parameter{ScalarParameter{T}}) where T
    return (length(p.payload.data),)
end

function _size(p::Parameter{ArrayParameter{T,N}}) where {T,N}
    return size(p.payload.data)
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
        Unexpected results may occur" maxlog=occursin(r"[^a-zA-Z0-9_ ]", transcode(String, copy(_name)))

    np = read(io, END(Int16))

    elsize = read(io, Int8)
    if elsize == -1
        T = String
    elseif elsize == 1
        T = Int8
    elseif elsize == 2
        T = Int16
    elseif elsize == 4
        T = eltype(END)
    else
        throw(ParameterTypeError("Bad parameter type size found. Got $(elsize), but only -1 (Char), 1 (Int8), 2 (Int16) and 4 (Float32) are valid"))
    end

    nd = read(io, UInt8)
    if nd > 0
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

    if nd > 0
        if elsize == -1
            if nd ≤ 2 # Vector{String}
                payload = StringParameter(data)
            else
                payload = ArrayParameter(elsize, nd, size(data), data)
            end
        elseif isone(prod(dims))
            # In the event of an 'array' parameter with only one element
            payload = ScalarParameter(data[1])
        else
            payload = ArrayParameter(elsize, nd, dims, data)
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

# Taken from Base.iscntrl and Base.isspace, but for bytes instead of chars
_iscntrl(c::Union{Int8,UInt8}) = c <= 0x1f || 0x7f <= c <= 0x9f
_isspace(c::Union{Int8,UInt8}) = c == 0x20 || 0x09 <= c <= 0x0d || c == 0x85 || 0xa0 <= c

function rstrip_cntrl_null_space(s)
    l = findlast(c -> !_iscntrl(c) && !_isspace(c), s)
    if isnothing(l)
        return @view s[end:end-1]
    else
        return @view s[begin:l]
    end
end

function _readarrayparameter(io::IO, ::Type{<:AbstractEndian{String}}, dims)::Array{String}
    tdata = Array{UInt8}(undef, dims)
    read!(io, tdata)

    if length(dims) > 1
        _, rdims... = dims
        data = Array{String}(undef, rdims)
        for ijk in CartesianIndices(data)
            data[ijk] = String(copy(rstrip_cntrl_null_space(@view tdata[:, ijk])))
        end
    else
        data = [ rstrip(String(tdata)) ]
    end
    return data
end

function Base.write(
    io::IO, p::Parameter{P}, ::Type{END}; last::Bool=false
) where {P,END<:AbstractEndian}
    nb = 0
    nb += write(io, flipsign(Int8(length(p._name)), -1*p.locked))
    nb += write(io, p.gid)
    nb += write(io, p._name)

    np::UInt16 = 5 + _ndims(p) + prod(_size(p))*abs(_elsize(p)) + length(p._desc)
    nb += write(io, last ? 0x0000 : END(UInt16)(np))

    elsize = _elsize(p)
    ndims = _ndims(p)
    dims = _size(p)

    nb += write(io, elsize |> Int8)
    nb += write(io, ndims |> Int8)
    if ndims > 0
        nb += sum(write.(io, Int8.(dims)))
    end

    elt = elsize == -1 ? Char :
          elsize == 1  ? UInt8 :
          elsize == 2 ? UInt16 : eltype(END)

    if elt <: Char
        if ndims > 1
            for s in p.payload.data
                _nb = write(io, s)
                _nb += write(io, collect(Iterators.repeated(0x00, Int(dims[1]) - _nb )))
                nb += _nb
            end
        else
            if p.payload.data isa Vector{String}
                if isempty(p.payload.data)
                    nb += sum(x -> write(io, 0x00), Iterators.repeated(0x00, prod(dims)); init=0)
                else
                    nb += write(io, only(p.payload.data))
                end
            else
                nb += write(io, p.payload.data)
            end
        end
    else
        nb += sum(write.(io, END(elt).(p.payload.data)))
    end

    nb += write(io, UInt8(length(p._desc)))
    if !isempty(p._desc)
        nb += write(io, p._desc)
    end

    return nb
end

function writesize(p::Parameter{P}) where {P}
    return 7 + length(p._name) + length(p._desc) + _ndims(p) + prod(_size(p))*abs(_elsize(p))
end

