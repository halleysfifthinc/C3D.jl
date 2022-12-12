@testset "readc3d kwargs, etc" begin
    @test f = readc3d(artifact"sample03/gait-pig.c3d"; strip_prefixes=true) isa C3DFile

    # issue #11
    @test_throws ArgumentError readc3d(artifact"sample00/Vicon Motion Systems/TableTennis.c3d"; strip_prefixes=true)
end
