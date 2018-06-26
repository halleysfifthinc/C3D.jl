@testset "Testing files with unusually large aspects" begin

     @testset "sample15 - More than 127 points" begin
         @test_nowarn readc3d(joinpath(datadir, "sample15", "FP1.C3D"))
         @test_nowarn readc3d(joinpath(datadir, "sample15", "FP2.C3D"))
     end

     @testset "sample17 - More than 128 channels" begin
         @test_nowarn readc3d(joinpath(datadir, "sample17",  "128analogchannels.c3d"))
     end

     @testset "sample19 - 34672 frames analog data" begin
         @test_nowarn readc3d(joinpath(datadir, "sample19",  "sample19.c3d"))
     end

     if isdir(joinpath(datadir, "sample31"))
         @testset "sample31 - more than 65535 frames" begin
             @test_nowarn readc3d(joinpath(datadir, "sample31", "large01.c3d"))
             @test_nowarn readc3d(joinpath(datadir, "sample31", "large02.c3d"))
         end
     end

     @testset "sample33 - DATA_START greater than 127" begin
         @test_nowarn readc3d(joinpath(datadir, "sample33",  "bigparlove.c3d"))
     end

end
