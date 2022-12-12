@testset "Corrupted/incorrect files" begin
    @test_nowarn readc3d(joinpath(artifact"sample18", "bad_parameter_section.c3d"))
end
