@testset "Corrupted/incorrect files" begin
    @test readc3d(joinpath(artifact"sample18", "bad_parameter_section.c3d")) isa C3DFile
end
