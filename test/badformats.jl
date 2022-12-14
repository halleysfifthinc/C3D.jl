@testset "Corrupted/incorrect files" begin
    @test readc3d(artifact"sample18/bad_parameter_section.c3d") isa C3DFile
    @test readc3d(artifact"sample27/kyowadengyo.c3d") isa C3DFile
end
