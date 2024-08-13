@testset "Testing files with unusually large aspects" begin

     @testset "More than 127 points" begin
         @test_nothrow readc3d(artifact"sample15/FP1.C3D")
         @test_nothrow readc3d(artifact"sample15/FP2.C3D")
         @test_nothrow readc3d(artifact"sample12/c24089 13.c3d")
     end

     @testset "sample17 - More than 128 channels" begin
         @test_nothrow readc3d(artifact"sample17/128analogchannels.c3d")
     end

     @testset "sample19 - 34672 frames analog data" begin
         @test_nothrow readc3d(artifact"sample19/sample19.c3d")
     end

     if haskey(ENV, "JULIA_C3D_TEST_SAMPLE31")
         @testset "sample31 - more than 65535 frames" begin
             @test_nothrow readc3d(artifact"sample31/large01.c3d")
             @test_nothrow readc3d(artifact"sample31/large02.c3d")
         end
     end

     @testset "sample33 - DATA_START greater than 127" begin
         @test_nothrow readc3d(artifact"sample33/bigparlove.c3d")
     end

end
