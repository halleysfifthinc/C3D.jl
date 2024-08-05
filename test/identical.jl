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

    @testset "sample01 files" begin
        comparefiles.(Ref(joinpath(artifact"sample01", sample01[1])), joinpath.(Ref(artifact"sample01"), sample01[2:end]))
    end
    @testset "sample02 files" begin
        comparefiles.(Ref(joinpath(artifact"sample02", sample02[1])), joinpath.(Ref(artifact"sample02"), sample02[2:end]))
    end
    @testset "sample08 files" begin
        comparefiles.(Ref(joinpath(artifact"sample08", sample08[1])), joinpath.(Ref(artifact"sample08"), sample08[2:end]))
    end
end

