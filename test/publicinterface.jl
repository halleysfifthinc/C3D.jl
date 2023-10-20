@testset "readc3d kwargs, etc" begin
    @test readc3d(artifact"sample01/Eb015pr.c3d"; paramsonly=true) isa C3DFile
    @test readc3d(artifact"sample01/Eb015pr.c3d"; paramsonly=true, validate=false) isa C3DFile
    @test readc3d(artifact"sample03/gait-pig.c3d"; strip_prefixes=true) isa C3DFile

    # issue #11
    @test_throws ArgumentError readc3d(artifact"sample00/Vicon Motion Systems/TableTennis.c3d"; strip_prefixes=true)

    # C3D length
    @test numpointframes(readc3d(artifact"sample36/18124framesi.c3d")) == 18124
    @test numpointframes(readc3d(artifact"sample36/18124framesf.c3d")) == 18124
    @test numpointframes(readc3d(artifact"sample36/36220framesi.c3d")) == 36220
    @test numpointframes(readc3d(artifact"sample36/36220framesf.c3d")) == 36220
    @test numpointframes(readc3d(artifact"sample36/72610framesi.c3d")) == 65535 # C3D.org mislabeled; confirmed via inspection in hex editor
    @test numpointframes(readc3d(artifact"sample36/72610framesf.c3d")) == 65535 # same for this one

    @test numanalogframes(readc3d(artifact"sample36/18124framesi.c3d")) == 0
    @test numanalogframes(readc3d(artifact"sample01/Eb015pr.c3d")) == 1800

    f = readc3d(artifact"sample01/Eb015pr.c3d")
    @test show(devnull, f) == nothing
    @test show(devnull, MIME("text/plain"), f) == nothing

    @testset "Show" begin
        @test show(devnull, readc3d(artifact"sample15/FP1.C3D")) === nothing
        @test show(devnull, readc3d(artifact"sample15/FP2.C3D")) === nothing
        @test show(devnull, readc3d(artifact"sample17/128analogchannels.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample19/sample19.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample31/large01.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample31/large02.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample33/bigparlove.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample03/gait-pig.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample00/Vicon Motion Systems/TableTennis.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/18124framesi.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/18124framesf.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/36220framesi.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/36220framesf.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/72610framesi.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/72610framesf.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample36/18124framesi.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample16/basketball.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample16/giant.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample16/golf.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample29/Facial-Sing.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample29/OptiTrack-IITSEC2007.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample34/AlbertoINT.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample34/AlbertoREAL.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample34/Basketball.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample35/Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample03/gait-pig.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample03/gait-pig-nz.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample18/bad_parameter_section.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample27/kyowadengyo.c3d")) === nothing
        @test show(devnull, readc3d(artifact"sample24/MotionMonitorC3D.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample15/FP1.C3D")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample15/FP2.C3D")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample17/128analogchannels.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample19/sample19.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample31/large01.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample31/large02.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample33/bigparlove.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample03/gait-pig.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample00/Vicon Motion Systems/TableTennis.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/18124framesi.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/18124framesf.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/36220framesi.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/36220framesf.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/72610framesi.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/72610framesf.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample36/18124framesi.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample16/basketball.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample16/giant.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample16/golf.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample29/Facial-Sing.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample29/OptiTrack-IITSEC2007.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample34/AlbertoINT.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample34/AlbertoREAL.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample34/Basketball.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample35/Mega Electronics Isokinetic EMG Angle Torque Sample File.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample03/gait-pig.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample03/gait-pig-nz.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample01/Eb015pr.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample18/bad_parameter_section.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample27/kyowadengyo.c3d")) === nothing
        @test show(devnull, MIME"text/plain"(), readc3d(artifact"sample24/MotionMonitorC3D.c3d")) === nothing
    end
end
