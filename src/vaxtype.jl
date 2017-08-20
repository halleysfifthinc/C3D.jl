# For dealing with C3D files in the DEC format (processor type 2)
primitive type Vax32 <: AbstractFloat 32 end

rotl32(x, k) = (x << k) | (x >> (-k & 31))

function Base.read(s::IOStream, T::Type{Vax32})
    return ccall(:jl_ios_get_nbyte_int, Vax32, (Ptr{Void}, Csize_t), s.ios, sizeof(T))
end

Base.convert(::Type{Float32}, x::Vax32) = reinterpret(Float32, rotl32(reinterpret(UInt32, x) & 0xfffffeff, 16))
Base.convert(::Type{Float64}, x::Vax32) = convert(Float64, reinterpret(Float32, rotl32(reinterpret(UInt32, x) & 0xfffffeff, 16)))

Base.promote_rule(::Type{T}, ::Type{Vax32}) where T <: Union{Float32,Float64} = T

export Vax32