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

end
