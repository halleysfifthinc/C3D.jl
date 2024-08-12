@testset "Comparing different files with identical data" begin
    sample01 = [ "Eb015pr.c3d",
                 "Eb015pi.c3d",
                 "Eb015vr.c3d",
                 "Eb015vi.c3d",
                 "Eb015sr.c3d",
                 "Eb015si.c3d" ]

    sample02 = [ "pc_real.c3d",
                 "pc_int.c3d",
                 "dec_real.c3d",
                 "dec_int.c3d",
                 "sgi_real.c3d",
                 "sgi_int.c3d" ]

    sample08 = [ "EB015PI.c3d",
                 "TESTAPI.c3d",
                 "TESTBPI.c3d",
                 "TESTCPI.c3d",
                 "TESTDPI.c3d" ]

    @testset "sample0[128] files internal consistency" begin
        @testset "$file" for file in vcat(
            joinpath.(Ref(artifact"sample01"), sample01),
            joinpath.(Ref(artifact"sample02"), sample02),
            joinpath.(Ref(artifact"sample08"), sample08))

            @test_internalconsistency readc3d(file)
        end
    end

    @testset "sample01" begin
        reference = joinpath(artifact"sample01", sample01[1])
        @testset "$(basename(reference)) vs. $(basename(candidate))" for candidate in sample01[2:end]
            comparefiles(reference, joinpath(artifact"sample01", candidate))
        end
    end
    @testset "sample02 files" begin
        reference = joinpath(artifact"sample02", sample02[1])
        @testset "$(basename(reference)) vs. $(basename(candidate))" for candidate in sample02[2:end]
            if candidate == "dec_int.c3d"
                # the dec_int.c3d file has a smattering of incorrect camera values for the
                # listed points (ie confirmed by looking at the binary, differs from the
                # other 5)
                # Example using "LFT2", the first sample is 0x1930-0x193F in pc_real.c3d and
                # 0x1898-0x189F in dec_int.c3d. The residual is stored at 0x193C and 0x189E
                # and is 0x46642400 and 0x3a09, respectively.
                # `(UInt16(reinterpret(Float32, 0x46642400)) == 0x3909) != 0x3a09`
                comparefiles(reference, joinpath(artifact"sample02", candidate);
                    ignore_cameras=["RFT2", "RSK1", "RSK2", "RSK3", "RTH1", "RTH3", "RPV2",
                        "LSK1", "LSK2", "LFT1", "LFT2", "RAR3", "RFA3", "LAR3", "LFA2",
                        "LFA3"])
            else
                comparefiles(reference, joinpath(artifact"sample02", candidate))
            end
        end
    end
    @testset "sample08 files" begin
        reference = joinpath(artifact"sample08", sample08[1])
        @testset "$(basename(reference)) vs. $(basename(candidate))" for candidate in sample08[2:end]
            comparefiles(reference, joinpath(artifact"sample08", candidate))
        end
    end
end

