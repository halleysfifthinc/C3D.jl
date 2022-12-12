@testset "Test files with only one source of data (point or analog)" begin

    @testset "Point only files" begin
        @test readc3d(joinpath(artifact"sample29", "Facial-Sing.c3d")) isa C3DFile
        samp29_1 = readc3d(joinpath(artifact"sample29", "Facial-Sing.c3d"))
        @test isempty(samp29_1.analog)
        @test readc3d(joinpath(artifact"sample29", "OptiTrack-IITSEC2007.c3d")) isa C3DFile
        samp29_2 = readc3d(joinpath(artifact"sample29", "OptiTrack-IITSEC2007.c3d"))
        @test isempty(samp29_1.analog)
        @test readc3d(joinpath(artifact"sample34", "AlbertoINT.c3d")) isa C3DFile
        samp34_1 = readc3d(joinpath(artifact"sample34", "AlbertoINT.c3d"))
        @test isempty(samp34_1.analog)
        @test readc3d(joinpath(artifact"sample34", "AlbertoREAL.c3d")) isa C3DFile
        samp34_2 = readc3d(joinpath(artifact"sample34", "AlbertoREAL.c3d"))
        @test isempty(samp34_2.analog)
        @test readc3d(joinpath(artifact"sample34", "Basketball.c3d")) isa C3DFile
        samp34_3 = readc3d(joinpath(artifact"sample34", "Basketball.c3d"))
        @test isempty(samp34_3.analog)
    end

    @testset "Analog only files" begin
        @test readc3d(joinpath(artifact"sample35", "Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")) isa C3DFile
        samp35 = readc3d(joinpath(artifact"sample35", "Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d"))
        @test isempty(samp35.point)
    end

end
