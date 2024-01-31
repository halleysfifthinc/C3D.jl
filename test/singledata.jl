@testset "Test files with only one source of data (point or analog)" begin

    @testset "Point only files" begin
        @test_nothrow readc3d(artifact"sample29/Facial-Sing.c3d")
        samp29_1 = readc3d(artifact"sample29/Facial-Sing.c3d")
        @test isempty(samp29_1.analog)
        @test_nothrow readc3d(artifact"sample29/OptiTrack-IITSEC2007.c3d")
        samp29_2 = readc3d(artifact"sample29/OptiTrack-IITSEC2007.c3d")
        @test isempty(samp29_1.analog)
        @test_nothrow readc3d(artifact"sample34/AlbertoINT.c3d")
        samp34_1 = readc3d(artifact"sample34/AlbertoINT.c3d")
        @test isempty(samp34_1.analog)
        @test_nothrow readc3d(artifact"sample34/AlbertoREAL.c3d")
        samp34_2 = readc3d(artifact"sample34/AlbertoREAL.c3d")
        @test isempty(samp34_2.analog)
        @test_nothrow readc3d(artifact"sample34/Basketball.c3d")
        samp34_3 = readc3d(artifact"sample34/Basketball.c3d")
        @test isempty(samp34_3.analog)
    end

    @testset "Analog only files" begin
        @test_nothrow readc3d(artifact"sample35/Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")
        samp35 = readc3d(artifact"sample35/Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")
        @test isempty(samp35.point)
    end

end
