@testitem "Corrupted/incorrect files" setup=[TestUtils] begin
using LazyArtifacts
# bad_parameter_section.c3d has duplicate labels
filter_duplicate_warnings() do
    @test_nothrow readc3d(artifact"sample18/bad_parameter_section.c3d")
    @test_nothrow readc3d(artifact"sample27/kyowadengyo.c3d")
end
end

# We cannot successfully read a file if the first record is invalid
@testitem "Invalid records" setup=[TestUtils] begin
    using LazyArtifacts
    src = artifact"sample01/Eb015pr.c3d"
    # The first record starts 4 bytes into the parameter section (whose 512-byte block number
    # is the first header byte); its first byte is the name length
    nonamelength = patchc3d(src) do bytes, c3d
        bytes[(bytes[1] - 1) * 512 + 5] = 0x00
    end
    @test_throws C3D.InvalidRecordError readc3d(nonamelength)
end
