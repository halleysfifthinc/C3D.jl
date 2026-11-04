@testitem "Corrupted/incorrect files" setup=[TestUtils] begin
using LazyArtifacts
# bad_parameter_section.c3d has duplicate labels
filter_duplicate_warnings() do
    @test_nothrow readc3d(artifact"sample18/bad_parameter_section.c3d")
    @test_nothrow readc3d(artifact"sample27/kyowadengyo.c3d")
end
end
