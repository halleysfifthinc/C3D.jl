abstract type AbstractEndian{T} end
struct LittleEndian{T} <: AbstractEndian{T}
    val::T
end
struct BigEndian{T} <: AbstractEndian{T}
    val::T
end
const LE = LittleEndian
const BE = BigEndian

export AbstractEndian, LittleEndian, BigEndian, LE, BE

Base.eltype(::Type{<:AbstractEndian{T}}) where {T} = T
(END::Type{<:AbstractEndian{T}})(x::U) where {T,U} = END(convert(T, x))
LE{T}(::Type{NT}) where {T,NT} = LE{NT}
BE{T}(::Type{NT}) where {T,NT} = BE{NT}
LE{T}(::Type{OT}) where {T,OT<:AbstractEndian} = LE{eltype(OT)}
BE{T}(::Type{OT}) where {T,OT<:AbstractEndian} = BE{eltype(OT)}

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

function Base.write(io::IO, x::LittleEndian{T}) where {T}
    return write(io, htol.(x.val))
end

function Base.write(io::IO, x::BigEndian{T}) where {T}
    return write(io, hton.(x.val))
end

function Base.write(io::IO, x::LittleEndian{VaxFloatF})
    return write(io, htol.(x.val).x)
end

function Base.write(io::IO, x::BigEndian{VaxFloatF})
    return write(io, hton.(x.val).x)
end

