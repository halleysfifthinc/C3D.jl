@testset "Testing files with unusually large aspects" begin

     @testset "sample15 - More than 127 points" begin
         @test readc3d(joinpath(artifact"sample15", "FP1.C3D")) isa C3DFile
         @test readc3d(joinpath(artifact"sample15", "FP2.C3D")) isa C3DFile
     end

     @testset "sample17 - More than 128 channels" begin
         @test readc3d(joinpath(artifact"sample17",  "128analogchannels.c3d")) isa C3DFile
     end

     @testset "sample19 - 34672 frames analog data" begin
         @test readc3d(joinpath(artifact"sample19",  "sample19.c3d")) isa C3DFile
     end

     if haskey(ENV, "JULIA_C3D_TEST_SAMPLE31")
         @testset "sample31 - more than 65535 frames" begin
             @test readc3d(joinpath(artifact"sample31", "large01.c3d")) isa C3DFile
             @test readc3d(joinpath(artifact"sample31", "large02.c3d")) isa C3DFile
         end
     end

     @testset "sample33 - DATA_START greater than 127" begin
         @test readc3d(joinpath(artifact"sample33",  "bigparlove.c3d")) isa C3DFile
     end

end
