# For dealing with C3D files in the DEC format (processor type 2)
primitive type Vax32 <: AbstractFloat 32 end

Vax32(x::UInt32) = reinterpret(Vax32, x)
Vax32(x::Float32) = convert(Vax32, x)

function Base.read(s::IOStream, T::Type{Vax32})
    return ccall(:jl_ios_get_nbyte_int, Vax32, (Ptr{Void}, Csize_t), s.ios, sizeof(T))
end

Base.show(io::IO, x::Vax32) = show(io, convert(Float64, x))

function Base.convert(::Type{Float32}, x::Vax32) 
    r = Ref{Float32}()
    ccall((:from_vax_r4, libvaxdata), Void, (Ref{Vax32}, Ref{Float32}, Ref{Int}), Ref(x), r, Ref(1))
    return r[]
end

function Base.convert(::Type{Vax32}, x::Float32) 
    r = Ref{Vax32}()
    ccall((:to_vax_r4, libvaxdata), Void, (Ref{Float32}, Ref{Vax32}, Ref{Int}), Ref(x), r, Ref(1))
    return r[]
end

function Base.convert{N}(::Type{Float32}, x::Array{Vax32,N}) 
    res = Array{Float32,N}(size(x))
    ccall((:from_vax_r4, libvaxdata), Void, (Ref{Vax32}, Ref{Float32}, Ref{Int}), Ref(x), res, Ref(length(x)))
    return res
end

function Base.convert{N}(::Type{Vax32}, x::Array{Float32,N}) 
    res = Array{Vax32,N}(size(x))
    ccall((:to_vax_r4, libvaxdata), Void, (Ref{Float32}, Ref{Vax32}, Ref{Int}), Ref(x), res, Ref(length(x)))
    return res
end

Base.convert(::Type{Float64}, x::Vax32) = convert(Float64, convert(Float32, x))

Base.promote_rule(::Type{T}, ::Type{Vax32}) where T <: Union{Float32,Float64} = T

export Vax32
