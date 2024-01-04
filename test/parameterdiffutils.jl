using DeepDiffs
using C3D: endianness, readparam

struct Repeated{T}
    r::T
    n::Int
end

function Base.show(io::IO, r::Repeated{T}) where T
    print(io, repr(r.r), "{$(r.n)}")
end

Base.iterate(r::Repeated, state=1) = state > r.n ? nothing : (r.r, state+1)
Base.eltype(::Type{Repeated{T}}) where T = T
Base.length(r::Repeated) = r.n
Base.size(r::Repeated) = (r.n,)
Base.size(r::Repeated, dim) = (dim == 1) ? r.n : 1

function Base.getindex(r::Repeated, i)
    1 ≤ i ≤ r.n || throw(BoundsError(r, i))
    return r.r
end

Base.firstindex(r::Repeated) = 1
Base.lastindex(r::Repeated) = length(r)

function condense(a::AbstractVector)
    b = similar(a, (0,))
    l = nothing
    c = 1

    for v in a
        if isnothing(l)
            push!(b, v)
        elseif v == l
            if c > 3
                push!(b, Repeated(v, c+1))
            else
                c += 1
            end
        else
            l = v
        end
    end
end

struct ParameterComparison
    ref::Vector{Any}
    comp::Vector{Any}
    type::Symbol

    function ParameterComparison(ref::Vector{UInt8}, comp::Vector{UInt8}, type, ::Type{END}=LE{Float32}) where {END<:AbstractEndian}
        type ∈ (:group, :parameter) || throw(ArgumentError("Invalid `type`; got $(type) but only `:group` or `:parameter` are valid."))
        _ref, _comp = [], []
        push!(_ref, Int(ref[1] % Int8))
        push!(_ref, ParameterField(Int(ref[2]), "GID"))
        append!(_ref, convert(Vector{Char}, ref[3:(2+abs(_ref[1]))]))
        push!(_ref, ParameterField(reinterpret(UInt16, ref[3+abs(_ref[1]):4+abs(_ref[1])])[1], "NP"))

        push!(_comp, Int(comp[1] % Int8))
        push!(_comp, ParameterField(Int(comp[2]), "GID"))
        append!(_comp, convert(Vector{Char}, comp[3:(2+abs(_comp[1]))]))
        push!(_comp, ParameterField(reinterpret(UInt16, comp[3+abs(_comp[1]):4+abs(_comp[1])])[1], "NP"))

        if type == :group
            push!(_ref, Int(ref[5+abs(_ref[1])]))
            append!(_ref, convert(Vector{Char}, ref[6+abs(_ref[1]):end]))

            push!(_comp, Int(comp[5+abs(_comp[1])]))
            append!(_comp, convert(Vector{Char}, comp[6+abs(_comp[1]):end]))
        else
            elsize = ref[5+abs(_ref[1])] % Int8 % Int
            ndims = Int(ref[6+abs(_ref[1])])
            dims = (Int8.(ref[7+abs(_ref[1]):6+abs(_ref[1])+ndims])...,)
            if elsize == -1
                v = Array{UInt8,ndims}(undef, dims)
            elseif elsize == 1
                v = Array{UInt8,ndims}(undef, dims)
            elseif elsize == 2
                v = Array{UInt16,ndims}(undef, dims)
            elseif elsize == 4
                v = Array{Float32,ndims}(undef, dims)
            else
                throw(error("Impossible elsize found"))
            end

            push!(_ref, ParameterField(elsize, elsize < 0 ? "Char" : string(eltype(v))))
            push!(_ref, ParameterField(ndims, ndims == 0 ? "scalar" : "ndims"))
            push!(_ref, dims)

            t = prod(dims)*abs(elsize)
            # @show elsize ndims dims t
            # @show 7+ndims+abs(_ref[1]):8+ndims+abs(_ref[1])+t sizeof(v) length(ref)
            # @show elsize, ndims, dims, t
            # @show 7+ndims+abs(_ref[1]):6+ndims+abs(_ref[1])+t length(ref)
            # # @show ref
            # @show String(copy(ref[7+ndims+abs(_ref[1]):6+ndims+abs(_ref[1])+t]))
            read!(IOBuffer(ref[7+ndims+abs(_ref[1]):6+ndims+abs(_ref[1])+t]), v, END(eltype(v)))
            if elsize == -1
                append!(_ref, convert(Array{Char}, v))
            else
                append!(_ref, v)
            end
            push!(_ref, ParameterField(Int(ref[7+ndims+abs(_ref[1])+t]), "desc. len")) # description length
            # @show _ref[end]
            append!(_ref, convert(Vector{Char}, ref[8+ndims+abs(_ref[1])+t:7+ndims+abs(_ref[1])+t+_ref[end].val]))


            # @show 5+abs(_comp[1])
            elsize = comp[5+abs(_comp[1])] % Int8 % Int
            ndims = Int(comp[6+abs(_comp[1])])
            dims = (comp[7+abs(_comp[1]):6+abs(_comp[1])+ndims] .% Int8...,)
            if elsize == -1
                v = Array{UInt8,ndims}(undef, dims)
            elseif elsize == 1
                v = Array{UInt8,ndims}(undef, dims)
            elseif elsize == 2
                v = Array{UInt16,ndims}(undef, dims)
            elseif elsize == 4
                v = Array{Float32,ndims}(undef, dims)
            else
                throw(error("Impossible elsize found: $elsize"))
            end

            push!(_comp, ParameterField(elsize, elsize < 0 ? "Char" : string(eltype(v))))
            push!(_comp, ParameterField(ndims, ndims == 0 ? "scalar" : "ndims"))
            push!(_comp, dims)

            t = prod(dims)*abs(elsize)
            # @show elsize, ndims, dims, t
            # @show 7+ndims+abs(_comp[1]):6+ndims+abs(_comp[1])+t length(comp)
            # @show String(copy(comp[7+ndims+abs(_comp[1]):6+ndims+abs(_comp[1])+t]))
            read!(IOBuffer(comp[7+ndims+abs(_comp[1]):6+ndims+abs(_comp[1])+t]), v, END(eltype(v)))
            if elsize == -1
                append!(_comp, convert(Array{Char}, v))
            else
                append!(_comp, v)
            end
            push!(_comp, ParameterField(Int(comp[7+ndims+abs(_comp[1])+t]), "desc. len")) # description length
            # @show _comp[end]
            append!(_comp, convert(Vector{Char}, comp[8+ndims+abs(_comp[1])+t:7+ndims+abs(_comp[1])+t+_comp[end].val]))
        end

        return new(_ref, _comp, type)
    end
end

function Base.:(==)(pc::ParameterComparison)
    pc.ref == pc.comp && return true

    reftype = pc.ref[pc.ref[1] + 4]
    comptype = pc.comp[pc.comp[1] + 4]

    refdims = pc.ref[pc.ref[1] + 6]
    compdims = pc.comp[pc.comp[1] + 6]

    if reftype == comptype == ParameterField(-1, "Char")
        if compdims[1] ≤ refdims[1]
            rd2 = checkindex(Bool, axes(refdims)[1], 2) ? refdims[2] : 1
            cd2 = checkindex(Bool, axes(compdims)[1], 2) ? compdims[2] : 1
            if rd2 == cd2
                if mapreduce(|, 1:rd2) do i
                        nl = pc.ref[1]
                        rg = 7+nl+i*refdims[1]-(refdims[1]-compdims[1]):6+nl+i*refdims[1]
                        all(isspace∘Char, pc.ref[rg])
                    end
                    return true
                end
            end
        end
    end

    return pc
end

struct ParameterField{T}
    val::T
    desc::String
end

Base.:(==)(a::ParameterField{T}, b::ParameterField{T}) where T = (a.desc == b.desc == "NP") ? true : a.val == b.val

function Base.show(io::IO, pf::ParameterField{T}) where T
    print(io, pf.val)
    printstyled(io, "::$(pf.desc)"; color=:light_black)

    return
end

function Base.show(io::IO, pc::ParameterComparison)
    if pc.type == :group
        print(io, deepdiff(pc.ref, pc.comp))
    else pc.type == :parameter
       print(io, deepdiff(pc.ref, pc.comp))
    end
end

function compare_parameters(f, group)
    _io = open(f.name)
    seek(_io, f.groups[group].pos)
    read(_io, typeof(f.groups[group]))
    _end = position(_io)
    seek(_io, f.groups[group].pos)
    ioA = IOBuffer(read(_io, _end - f.groups[group].pos))
    close(_io)
    ioB = IOBuffer()
    write(ioB, f.groups[group])

    return ParameterComparison(take!(ioA), take!(ioB), :group)
end

function compare_parameters(f, group, parameter)
    _io = open(f.name)
    seek(_io, f.groups[group].params[parameter].pos)
    readparam(_io, endianness(f))
    _end = position(_io)
    seek(_io, f.groups[group].params[parameter].pos)
    ioA = IOBuffer(read(_io, _end - f.groups[group].params[parameter].pos))
    close(_io)
    ioB = IOBuffer()
    write(ioB, f.groups[group].params[parameter], endianness(f))

    A = take!(ioA)
    B = take!(ioB)
    return ParameterComparison(A, B, :parameter)
end

