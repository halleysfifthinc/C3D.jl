using C3D: Group, Parameter, gid,
    push_extended_param!, delete_extended_param!, _find_in_extended,
    get_extended_parameter_names

"""Helper to create a minimal group with USED and the given parameters."""
function _make_group(; used::Int=0, params...)
    g = Group("TEST", "")
    g[:USED] = Parameter(:USED, "", used)
    for (k, v) in params
        g[k] = Parameter(k, "", v)
    end
    return g
end

"""Push `n` labels (and increment USED each time)."""
function _push_n!(g, base, n; prefix="L")
    for i in 1:n
        push_extended_param!(g, base, "$prefix$i")
        g.params[:USED].payload.data += 1
    end
end

@testset verbose=true "push/delete_extended_param!" begin
    @testset "push into empty array" begin
        g = _make_group(; LABELS=String[])
        push_extended_param!(g, :LABELS, "A")
        @test g[:LABELS] == ["A"]
    end

    @testset "push overwrites trash beyond USED" begin
        g = _make_group(; used=2, LABELS=["X", "Y", "trash1", "trash2"])
        push_extended_param!(g, :LABELS, "Z")
        @test g[:LABELS][3] == "Z"
        # Array length unchanged (overwrite, not insert)
        @test length(g[:LABELS]) == 4
    end

    @testset "push creates overflow at 255 boundary" begin
        g = _make_group(; used=255, LABELS=fill("", 255))

        # 256th push should create LABELS2
        push_extended_param!(g, :LABELS, "L256")
        g.params[:USED].payload.data += 1
        @test haskey(g, :LABELS2)
        @test g[:LABELS2] == ["L256"]
        @test length(g[:LABELS]) == 255
    end

    @testset "push creates param chain when absent and USED > 255" begin
        g = _make_group(; used=256)

        # UNITS doesn't exist. Pushing should create UNITS (255 empties) + UNITS2 (value)
        push_extended_param!(g, :UNITS, "mV")
        @test haskey(g, :UNITS)
        @test length(g[:UNITS]) == 255
        @test haskey(g, :UNITS2)
        @test all(==(""), g[:UNITS])
        @test g[:UNITS2] == ["mV"]
    end

    @testset "pop from single param" begin
        g = _make_group(; used=3, LABELS=["A", "B", "C"])
        delete_extended_param!(g, :LABELS, 2)
        @test g[:LABELS] == ["A", "C"]
    end

    @testset "pop cascades across overflow boundary" begin
        g = _make_group(; used=257,
            LABELS=["L$i" for i in 1:255])
        g[:LABELS2] = Parameter(:LABELS2, "", ["L256", "L257"])

        delete_extended_param!(g, :LABELS, 255)
        # L256 should cascade from LABELS2[1] → LABELS[255]
        @test g[:LABELS][end] == "L256"
        @test length(g[:LABELS]) == 255
        @test g[:LABELS2] == ["L257"]
    end

    @testset "pop is no-op for missing param or out-of-range pos" begin
        g = _make_group(; used=3, LABELS=["A", "B"])
        # pos=3 exceeds array length — should not error
        delete_extended_param!(g, :LABELS, 3)
        @test g[:LABELS] == ["A", "B"]
    end

    @testset "_find_in_extended" begin
        g = _make_group(; used=257,
            LABELS=["L$i" for i in 1:255])
        g[:LABELS2] = Parameter(:LABELS2, "", ["L256", "L257"])

        @test _find_in_extended(g, :LABELS, "L1") == 1
        @test _find_in_extended(g, :LABELS, "L255") == 255
        @test _find_in_extended(g, :LABELS, "L256") == 256
        @test _find_in_extended(g, :LABELS, "L257") == 257
        @test _find_in_extended(g, :LABELS, "NOPE") === nothing
        # Missing param returns nothing
        @test _find_in_extended(g, :UNITS, "mV") === nothing
    end
end
