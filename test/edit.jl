@testset "Editing" begin
    # Shared test data
    sample01_fn = joinpath(artifact"sample01", "Eb015pr.c3d")
    sample03_fn = joinpath(artifact"sample03", "gait-pig.c3d")
    sample08_fn = joinpath(artifact"sample08", "TESTAPI.c3d")
    sample10_fn = joinpath(artifact"sample10", "Sample10", "TYPE-2.C3D")

    @testset "deletepoint!" begin
        f = readc3d(sample01_fn)
        name = first(keys(f.point))
        used = f.groups[:POINT][Int, :USED]
        desc_len = length(f.groups[:POINT][Vector{String}, :DESCRIPTIONS])

        @test_throws ArgumentError deletepoint!(f, "DOESNOTEXIST")

        deletepoint!(f, name)
        @test name ∉ f.groups[:POINT][Vector{String}, :LABELS]
        @test !haskey(f.point, name)
        @test !haskey(f.residual, name)
        @test !haskey(f.cameras, name)
        @test f.groups[:POINT][Int, :USED] == used - 1
        @test length(f.groups[:POINT][Vector{String}, :DESCRIPTIONS]) == desc_len - 1
        @test_internalconsistency(f)

        for name in collect(keys(f.point))
            deletepoint!(f, name)
        end
        @test f.groups[:POINT][Int, :USED] == 0
        @test isempty(f.point)
        @test isempty(f.residual)
        @test isempty(f.cameras)
        @test_internalconsistency(f)

        @testset "round-trip preserves deletion" begin
            f = readc3d(sample01_fn)
            name = first(keys(f.point))
            deletepoint!(f, name)

            path, io = mktemp()
            close(io)
            writec3d(path, f)
            f2 = readc3d(path)
            rm(path)

            @test !haskey(f2.point, name)
            @test_internalconsistency(f2)
        end

        @testset "removing a pseudo-marker (ANGLES/FORCES/MOMENTS/POWERS)" begin
            f = readc3d(sample03_fn)
            angles = f.groups[:POINT][Vector{String}, :ANGLES]
            name = first(angles)
            @test haskey(f.point, name)
            deletepoint!(f, name)
            @test name ∉ f.groups[:POINT][Vector{String}, :ANGLES]
            @test_internalconsistency(f)
        end
    end

    @testset "deleteanalog!" begin
        f = readc3d(sample01_fn)
        # Use a non-force-plate channel for basic deletion tests
        name = "CH7"
        @test haskey(f.analog, name)
        used = f.groups[:ANALOG][Int, :USED]
        orig_lengths = Dict(
            param => length(f.groups[:ANALOG][param])
            for param in (:DESCRIPTIONS, :UNITS, :SCALE, :OFFSET)
            if haskey(f.groups[:ANALOG], param))

        @test_throws ArgumentError deleteanalog!(f, "DOESNOTEXIST")

        deleteanalog!(f, name)
        @test !haskey(f.analog, name)
        @test f.groups[:ANALOG][Int, :USED] == used - 1
        @test name ∉ f.groups[:ANALOG][Vector{String}, :LABELS]
        for (param, orig_len) in orig_lengths
            @test length(f.groups[:ANALOG][param]) == orig_len - 1
        end
        @test_internalconsistency(f)

        @testset "refuses force plate channels" begin
            f = readc3d(sample01_fn)
            @test_throws ArgumentError deleteanalog!(f, "FX1")
        end

        @testset "round-trip preserves deletion" begin
            f = readc3d(sample01_fn)
            deleteanalog!(f, "CH7")

            path, io = mktemp()
            close(io)
            writec3d(path, f)
            f2 = readc3d(path)
            rm(path)

            @test !haskey(f2.analog, "CH7")
            @test_internalconsistency(f2)
        end
    end

    @testset "deleteforceplate!" begin
        f = readc3d(sample01_fn)
        n_plates = f.groups[:FORCE_PLATFORM][Int, :USED]
        used = f.groups[:ANALOG][Int, :USED]
        # Plate 1 channels
        fp_channel = f.groups[:FORCE_PLATFORM][:CHANNEL]
        labels = f.groups[:ANALOG][Vector{String}, :LABELS]
        plate1_names = [labels[Int(fp_channel[r, 1])] for r in axes(fp_channel, 1)
                        if fp_channel[r, 1] > 0]

        @test_throws ArgumentError deleteforceplate!(f, 0)
        @test_throws ArgumentError deleteforceplate!(f, n_plates + 1)

        deleteforceplate!(f, 1)
        @test f.groups[:FORCE_PLATFORM][Int, :USED] == n_plates - 1
        @test f.groups[:ANALOG][Int, :USED] == used - length(plate1_names)
        for name in plate1_names
            @test !haskey(f.analog, name)
        end
        @test_internalconsistency(f)

        @testset "CHANNEL indices remapped" begin
            # After removing plate 1, the remaining plate's channels should point
            # to valid analog indices
            if f.groups[:FORCE_PLATFORM][Int, :USED] > 0
                new_channel = f.groups[:FORCE_PLATFORM][:CHANNEL]
                new_labels = f.groups[:ANALOG][Vector{String}, :LABELS]
                new_used = f.groups[:ANALOG][Int, :USED]
                for idx in new_channel
                    idx == 0 && continue
                    @test 1 ≤ idx ≤ new_used
                end
            end
        end

        @testset "round-trip preserves deletion" begin
            f = readc3d(sample01_fn)
            deleteforceplate!(f, 1)

            path, io = mktemp()
            close(io)
            writec3d(path, f)
            f2 = readc3d(path)
            rm(path)

            @test f2.groups[:FORCE_PLATFORM][Int, :USED] == n_plates - 1
            @test_internalconsistency(f2)
        end

        @testset "GAIN handled" begin
            # sample10 TYPE-2 has GAIN — all channels are FP channels
            f = readc3d(sample10_fn)
            @test haskey(f.groups[:ANALOG], :GAIN)
            orig_gain_len = length(f.groups[:ANALOG][:GAIN])
            n_ch = size(f.groups[:FORCE_PLATFORM][:CHANNEL], 1)
            deleteforceplate!(f, 1)
            @test length(f.groups[:ANALOG][:GAIN]) == orig_gain_len - n_ch

            # sample01 has no GAIN — should not error
            f2 = readc3d(sample01_fn)
            @test !haskey(f2.groups[:ANALOG], :GAIN)
            @test_nothrow deleteforceplate!(f2, 1)
        end
    end
end
