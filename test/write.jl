using C3D: _elsize, _ndims, _size, writesize

@testset "Writing" begin
    artifacts = keys(parsefile(find_artifacts_toml(@__FILE__)))
    # Test that headers can read/write round-trip identically
    @testset "Headers" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        # Those files are incomplete (end is cut off)
        art == "sample13" && basename(fn) in ("Dance.c3d", "golfswing.c3d") &&
            continue

        ref, comp = compareheader(fn)
        @test ref == comp
    end
    end
    end

    # Test that groups can read/write round-trip identically
    @testset "Groups" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        f = readc3d(fn; paramsonly=true)
        gs = keys(f.groups)

        for g in gs
            @test write(IOBuffer(), f.groups[g]) == writesize(f.groups[g])
            @test ==(compare_parameters(f, g))
        end
    end
    end
    end

    # Test that parameters can read/write round-trip identically (trimmed white-space is
    # ignored)
    @testset "Parameters:" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        f = readc3d(fn; paramsonly=true)
        fio = open(fn)
        gs = keys(f.groups)
        ps = [ (g,p) for g in gs for p in keys(f.groups[g].params) ]

        for (g,p) in ps
            @test write(IOBuffer(), f.groups[g].params[p], endianness(f)) == writesize(f.groups[g].params[p])

            # :GROUP and :PARAMETER are placeholders that are replaced with the actual
            # group and parameter names
            expr = :(==(compare_parameters($f, :GROUP, :PARAMETER)))
            expr.args[2].args[3] = QuoteNode(g) # replace :GROUP with g
            expr.args[2].args[4] = QuoteNode(p) # same for :PARAMETER

            # eval so that the group and parameter symbols appear as literals for
                # readability if the test fails
            @eval @test $expr
        end
    end
    end
    end

    @testset "Data:" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        # these 2 artifact"sample30" files have incorrectly formated residuals that we don't
        # intend to replicate/match (we fail to read because of the incorrect residuals)
        fn == artifact"sample30/admarche2.c3d" && continue
        fn == artifact"sample30/marche281.c3d" && continue

        # this is an out-of-spec file where the ANALOG:RATE is not an integer multiple of the
        # POINT:RATE. We will read this, but we will not support writing this
        fn == artifact"sample11/evart.c3d" && continue

        failanalog=false

        # non-integer samples in original file that are correctly(?) rounded to integers on write
        # Absolute difference of [2.6020852f-17, 5.2041704f-17], 2 samples
        fn == artifact"sample00/Innovative Sports Training/Static Pose.c3d" && (failanalog=true;)
        # Absolute difference of 8.673617f-18, 2 samples
        fn == artifact"sample00/Innovative Sports Training/Gait with EMG.c3d" && (failanalog=true;)

        ref, comp = comparedata(fn)
        refdata, (refpoint, refresidual, refanalog) = ref
        compdata, (comppoint, compresidual, companalog) = comp

        nan_equal(x,y) = (isnan(x) && isnan(y)) || x == y
        passpoint = @test mapreduce(nan_equal, &, refpoint, comppoint)
        passresidual = @test mapreduce(nan_equal, &, refresidual, compresidual)
        passanalog = @test mapreduce(nan_equal, &, refanalog, companalog) broken=failanalog
        fails = any(p -> !(p isa Test.Pass), (passpoint, passresidual, passanalog))

        # artifact"sample27/kyowadengyo.c3d" contains analog contentful(?) channels scaled by
        # zero; leading to differences betwee original and written data; although the
        # read/processed data in the analog channels remains the same (±0)
        fn == artifact"sample27/kyowadengyo.c3d" && (fails=true;)

        # residuals are (incorrectly) stored as unsigned int's but (correctly) written as signed ints
        fn == artifact"sample05/vicon512.c3d" && (fails=true;)
        fn == artifact"sample03/gait-pig-nz.c3d" && (fails=true;)
        fn == artifact"sample12/c24089 13.c3d" && (fails=true;) # slow read; add to benchmarks and/or profile
        fn == artifact"sample07/16bitanalog.c3d" && (fails=true;)
        fn == artifact"sample23/Vicon_analysis.c3d" && (fails=true;)
        # the following also have (one-time) floating-point non-cummutativity in the analog data
        fn == artifact"sample17/128analogchannels.c3d" && (fails=true;)
        fn == artifact"sample26/Capture0002.c3d" && (fails=true;)
        fn == artifact"sample26/Capture0003.c3d" && (fails=true;)
        fn == artifact"sample26/Capture0004.c3d" && (fails=true;)
        fn == artifact"sample26/Capture0008_Standing.c3d" && (fails=true;)
        fn == artifact"sample26/Standing_Hybrid_2.c3d" && (fails=true;)
        fn == artifact"sample26/Walking_Hybrid_1_1.c3d" && (fails=true;)
        fn == artifact"sample26/Walking_Hybrid_1_2.c3d" && (fails=true;)
        fn == artifact"sample26/Walking_Hybrid_1_3.c3d" && (fails=true;)
        fn == artifact"sample26/Walking_Hybrid_1_4.c3d" && (fails=true;)
        fn == artifact"sample26/Walking_Hybrid_1_5.c3d" && (fails=true;)
        fn == artifact"sample26/Walking_Hybrid_2.c3d" && (fails=true;)

        # floating-point non-commutativity in analog data; these changes are one-time (ie if
        # read then write the same file sequentially, all files after the first will be exactly
        # identical)
        # 52.0f0 * -0.05f0 / -0.05f0 != 52.0f0
        fn == artifact"sample00/Codamotion/codamotion_gaitwands_19970212.c3d" && (fails=true;)
        # (-27.32653f0 * (1.0f0 * 0.0048828125f0) / (1.0f0 * 0.0048828125f0) + -0.0f0 != -27.32653f0
        fn == artifact"sample24/MotionMonitorC3D.c3d" && (fails=true;)

        # Compare raw binary data from original and written files
        if checkindex(Bool, eachindex(refdata), length(compdata))
            @test @view(refdata[begin:length(compdata)]) == compdata broken=fails
        elseif checkindex(Bool, eachindex(compdata), length(refdata))
            @test refdata == @view(compdata[begin:length(refdata)]) broken=fails
        end
    end
    end
    end
end
