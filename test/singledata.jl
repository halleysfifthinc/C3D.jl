@testset "Test files with only one source of data (point or analog)" begin

    @testset "Point only files" begin
        samp29_1 = @test_nowarn readc3d(joinpath(artifact"sample29", "Facial-Sing.c3d"))
        @test isempty(samp29_1.analog)
        samp29_2 = @test_nowarn readc3d(joinpath(artifact"sample29", "OptiTrack-IITSEC2007.c3d"))
        @test isempty(samp29_1.analog)
        samp34_1 = @test_nowarn readc3d(joinpath(artifact"sample34", "AlbertoINT.c3d"))
        @test isempty(samp34_1.analog)
        samp34_2 = @test_nowarn readc3d(joinpath(artifact"sample34", "AlbertoREAL.c3d"))
        @test isempty(samp34_2.analog)
        samp34_3 = @test_nowarn readc3d(joinpath(artifact"sample34", "Basketball.c3d"))
        @test isempty(samp34_3.analog)
    end

    @testset "Analog only files" begin
        samp35 = @test_nowarn readc3d(joinpath(artifact"sample35", "Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d"))
        @test isempty(samp35.point)
    end

end
