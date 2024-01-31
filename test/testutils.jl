using DeepDiffs
using C3D: AbstractEndian, LE, endianness, readparam

macro test_nothrow(ex)
    esc(:(@test ($(ex); true)))
end

function comparefiles(reference, candidate)
    @test_nothrow readc3d(reference; missingpoints=false)
    ref = readc3d(reference; missingpoints=false)

    @test_nothrow readc3d(candidate; missingpoints=false)
    cand = readc3d(candidate; missingpoints=false)

    @testset "Comparison between $(basename(reference)) and $(basename(candidate))" begin
        @testset "Parameters equivalency between files" begin
            @testset "Compare groups with C3DFile(\"…/$(basename(reference))\")" begin
                @test keys(ref.groups) ⊆ keys(cand.groups)
                for grp in keys(ref.groups)
                    @testset "Compare the :$(ref.groups[grp].name) parameters with C3DFile(\"…/$(basename(reference))\")" begin
                        @test keys(ref.groups[grp].params) ⊆ keys(cand.groups[grp].params)
                        for param in keys(ref.groups[grp].params)
                            if eltype(ref.groups[grp].params[param].payload.data) <: Number
                                if grp == :POINT && param == :SCALE
                                    @test abs.(ref.groups[grp].params[param].payload.data) ≈ abs.(cand.groups[grp].params[param].payload.data)
                                elseif grp == :POINT && param == :DATA_START
                                    if any(basename(candidate) .== ("TESTBPI.c3d", "TESTCPI.c3d", "TESTDPI.c3d"))
                                        @test cand.groups[grp].params[param].payload.data == 20
                                    else
                                        continue
                                    end
                                else
                                    @test ref.groups[grp].params[param].payload.data ≈ cand.groups[grp].params[param].payload.data
                                end
                            else
                                @test ref.groups[grp].params[param].payload.data == cand.groups[grp].params[param].payload.data
                            end
                        end
                    end
                end
            end
        end

        @testset "Data equivalency between file types" begin
            @testset "Ensure data equivalency between C3DFile(\"…/$(basename(candidate))\") and C3DFile(\"…/$(basename(reference))\")" begin
                for sig in keys(ref.point)
                    @testset "$sig" begin
                        @test haskey(cand.point,sig)
                        @test all(isapprox.(ref.point[sig], cand.point[sig]; atol=0.3)) skip=(!haskey(cand.point, sig))
                        @test ref.residual[sig] ≈ cand.residual[sig] skip=(!haskey(cand.point, sig))
                        @test mapreduce((x,y) -> isapprox(x, y, atol=1), |, ref.cameras[sig], cand.cameras[sig]) skip=(!haskey(cand.point, sig))
                    end
                end
                for sig in keys(ref.analog)
                    @testset "$sig" begin
                        @test haskey(cand.analog,sig)
                        @test all(isapprox.(ref.analog[sig], cand.analog[sig]; atol=0.3)) skip=(!haskey(cand.analog, sig))
                    end
                end
            end
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

