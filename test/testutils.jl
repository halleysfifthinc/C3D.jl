using DeepDiffs, Test
using C3D: AbstractEndian, LE, endianness, readparam
using C3D: rstrip_cntrl_null_space as _rstrip

macro test_nothrow(ex)
    esc(:(@test ($(ex); true)))
end

macro test_internalconsistency(f)
    esc(quote
        @test length(($f).point) == ($f).groups[:POINT][Int, :USED]
        @test length(($f).residual) == ($f).groups[:POINT][Int, :USED]
        @test length(($f).cameras) == ($f).groups[:POINT][Int, :USED]
        @test length(($f).analog) == ($f).groups[:ANALOG][Int, :USED]
    end)
end

function readdir_recursive(dir; join=false)
    outfiles = String[]
    for (root, dirs, files) in walkdir(dir)
        if join
            append!(outfiles, joinpath.(root, files))
        else
            append!(outfiles, files)
        end
    end

    return outfiles
end

function comparedata(fn)
    f = readc3d(fn)
    datastart = (f.header.datastart - 1)*512
    fio = open(fn)
    seek(fio, datastart)
    refdata = read(fio)
    seek(fio, datastart)

    format = f.groups[:POINT][Float32, :SCALE] > 0 ? Int16 : eltype(endianness(f))::Type
    ref = C3D.readdata(fio, f.header, f.groups, format)

    compio = IOBuffer()
    nb = C3D.writedata(compio, f)
    compdata = take!(copy(compio))

    seekstart(compio)
    comp = C3D.readdata(compio, C3D.Header(f), f.groups, format)

    return (refdata, ref), (compdata, comp)
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
        refnl = Int(ref[1] % Int8)
        push!(_ref, refnl)
        refnl = abs(refnl)
        push!(_ref, ParameterField(Int(ref[2]), "GID"))
        append!(_ref, convert(Vector{Char}, ref[3:(2+refnl)]))
        push!(_ref, ParameterField(reinterpret(UInt16, ref[3+refnl:4+refnl])[1], "NP"))

        compnl = Int(comp[1] % Int8)
        push!(_comp, compnl)
        compnl = abs(compnl)
        push!(_comp, ParameterField(Int(comp[2]), "GID"))
        append!(_comp, convert(Vector{Char}, comp[3:(2+compnl)]))
        push!(_comp, ParameterField(reinterpret(UInt16, comp[3+compnl:4+compnl])[1], "NP"))

        if type == :group
            push!(_ref, Int(ref[5+refnl]))
            append!(_ref, convert(Vector{Char}, ref[6+refnl:end]))

            push!(_comp, Int(comp[5+compnl]))
            append!(_comp, convert(Vector{Char}, comp[6+compnl:end]))
        else
            elsize = ref[5+refnl] % Int8 % Int
            ndims = Int(ref[6+refnl])
            dims = (Int.(ref[7+refnl:6+refnl+ndims])...,)
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
            # @show 7+ndims+refnl:8+ndims+refnl+t sizeof(v) length(ref)
            # @show elsize, ndims, dims, t
            # @show 7+ndims+refnl:6+ndims+refnl+t length(ref)
            # # @show ref
            # @show String(copy(ref[7+ndims+refnl:6+ndims+refnl+t]))
            read!(IOBuffer(ref[7+ndims+refnl:6+ndims+refnl+t]), v, END(eltype(v)))
            if elsize == -1
                append!(_ref, convert(Array{Char}, v))
            else
                append!(_ref, v)
            end
            push!(_ref, ParameterField(Int(ref[7+ndims+refnl+t]), "desc. len")) # description length
            # @show _ref[end]
            append!(_ref, convert(Vector{Char}, ref[8+ndims+refnl+t:7+ndims+refnl+t+_ref[end].val]))


            # @show 5+compnl
            elsize = comp[5+compnl] % Int8 % Int
            ndims = Int(comp[6+compnl])
            dims = (comp[7+compnl:6+compnl+ndims] .% Int...,)
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
            # @show 7+ndims+compnl:6+ndims+compnl+t length(comp)
            # @show String(copy(comp[7+ndims+compnl:6+ndims+compnl+t]))
            read!(IOBuffer(comp[7+ndims+compnl:6+ndims+compnl+t]), v, END(eltype(v)))
            if elsize == -1
                append!(_comp, convert(Array{Char}, v))
            else
                append!(_comp, v)
            end
            push!(_comp, ParameterField(Int(comp[7+ndims+compnl+t]), "desc. len")) # description length
            # @show _comp[end]
            append!(_comp, convert(Vector{Char}, comp[8+ndims+compnl+t:7+ndims+compnl+t+_comp[end].val]))
        end

        return new(_ref, _comp, type)
    end
end

function drop_trivial(dims)
    if length(dims) > 1
        dropped..., trivial = dims
    else
        dropped = dims
        trivial = ()
    end

    if !isempty(trivial) && isone(trivial)
        return drop_trivial(dropped)
    else
        return dims
    end
end

function Base.:(==)(pc::ParameterComparison)
    pc.ref == pc.comp && return true

    matches = true

    refnl = abs(pc.ref[1])
    compnl = abs(pc.comp[1])
    matches &= pc.ref[3:refnl] == pc.comp[3:compnl]
    matches || return false

    reftype = pc.ref[refnl + 4]
    comptype = pc.comp[compnl + 4]
    matches &= reftype == comptype
    matches || return false

    refndims = pc.ref[refnl + 5]
    compndims = pc.comp[compnl + 5]

    refdims = pc.ref[refnl + 6]
    compdims = pc.comp[compnl + 6]

    # mismatched dims if the array is ultimately empty aren't significant
    prod(compdims) == prod(refdims) == 0 && return true

    if compndims.val ≤ refndims.val
        simple_refdims = drop_trivial(refdims)
        simple_compdims = drop_trivial(compdims)

        if reftype == comptype == ParameterField(-1, "Char")
            if length(simple_compdims) ≤ length(simple_refdims)
                @assert checkindex(Bool, axes(pc.ref,1), (refnl+7):(refnl+7+prod(simple_refdims)))
                @assert checkindex(Bool, axes(pc.comp,1), (compnl+7):(compnl+7+prod(simple_compdims)))

                refrg = (refnl+7):(refnl+6+prod(simple_refdims))
                comprg = (compnl+7):(compnl+6+prod(simple_compdims))

                if length(simple_compdims) == 1
                    @views matches &= _rstrip(pc.ref[refrg]) == _rstrip(pc.comp[comprg])
                    matches || return false
                else
                    refdata = reshape(@view(pc.ref[refrg]), simple_refdims)
                    compdata = reshape(@view(pc.comp[comprg]), simple_compdims)
                    @debug "" refdata compdata _module=C3D

                    matches &= simple_compdims[2:end] == simple_refdims[2:end]
                    matches || return false

                for (refijk, compijk) in zip(CartesianIndices(axes(refdata)[2:end]), CartesianIndices(axes(compdata)[2:end]))
                @debug "" String(Vector{UInt8}(_rstrip(refdata[:, refijk]))) String(Vector{UInt8}(_rstrip(compdata[:, compijk]))) _module=C3D
                        matches &= _rstrip(refdata[:, refijk]) == _rstrip(compdata[:, compijk])
                    end
                end
            else
                return false
            end

            # if rd2 == cd2
            #     if mapreduce(|, 1:rd2) do i
            #             nl = pc.ref[1]
            #             rg = 7+nl+i*refdims[1]-(refdims[1]-compdims[1]):6+nl+i*refdims[1]
            #             all(isspace∘Char, pc.ref[rg])
            #         end
            #         return true
            #     end
            # end
        end
    elseif compndims != refndims
        return false
    else # compndims == refndims
    end

    matches && return true

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
    ioB = IOBuffer()
    write(ioB, f.groups[group])
    if !iszero(f.groups[group].pos)
        _io = open(f.name)
        seek(_io, f.groups[group].pos)
        read(_io, typeof(f.groups[group]))
        _end = position(_io)
        seek(_io, f.groups[group].pos)
        ioA = IOBuffer(read(_io, _end - f.groups[group].pos))
        close(_io)
    else # Group didn't exist in file
        ioA = copy(ioB)
    end

    return ParameterComparison(take!(ioA), take!(ioB), :group)
end

function compare_parameters(f, group, parameter)
    ioB = IOBuffer()
    write(ioB, f.groups[group].params[parameter], endianness(f))

    if !iszero(f.groups[group].params[parameter].pos)
        _io = open(f.name)
        seek(_io, f.groups[group].params[parameter].pos)
        readparam(_io, endianness(f))
        _end = position(_io)
        seek(_io, f.groups[group].params[parameter].pos)
        ioA = IOBuffer(read(_io, _end - f.groups[group].params[parameter].pos))
        close(_io)
    else # Parameter didn't exist in file
        ioA = copy(ioB)
    end

    return ParameterComparison(take!(ioA), take!(ioB), :parameter)
end

