@testitem "Point only files" setup=[TestUtils] begin
    using LazyArtifacts
        @test_nothrow readc3d(artifact"sample29/Facial-Sing.c3d")
        samp29_1 = readc3d(artifact"sample29/Facial-Sing.c3d")
        @test isempty(samp29_1.analog)
        @test_nothrow readc3d(artifact"sample29/OptiTrack-IITSEC2007.c3d")
        samp29_2 = readc3d(artifact"sample29/OptiTrack-IITSEC2007.c3d")
        @test isempty(samp29_2.analog)
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

@testitem "Analog only files" setup=[TestUtils] begin
    using LazyArtifacts
        @test_nothrow readc3d(artifact"sample35/Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")
        samp35 = readc3d(artifact"sample35/Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")
        @test isempty(samp35.point)
end
