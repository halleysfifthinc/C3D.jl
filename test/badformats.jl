@testitem "Corrupted/incorrect files" setup=[TestUtils] begin
using LazyArtifacts
# bad_parameter_section.c3d has duplicate labels
filter_duplicate_warnings() do
    @test_nothrow readc3d(artifact"sample18/bad_parameter_section.c3d")
    @test_nothrow readc3d(artifact"sample27/kyowadengyo.c3d")
end
end

# Files that `readc3d` declines to read (the "not a valid C3D file" error is tested in
# "Validation"); each fixture is a valid sample with one field corrupted
@testitem "Irrecoverable format errors" setup=[TestUtils] begin
    using LazyArtifacts
    src = artifact"sample01/Eb015pr.c3d" # little-endian, so the patched bytes are LE

    # The processor-type byte is the 4th byte of the parameter section; only 0x54, 0x55, and
    # 0x56 are defined
    badproc = patchc3d(src) do bytes, c3d
        bytes[(bytes[1] - 1) * 512 + 4] = 0x57
    end
    @test_throws C3D.IrrecoverableFormatError readc3d(badproc)

    # We cannot successfully read a file if the first record is invalid
    nonamelength = patchc3d(src) do bytes, c3d
        bytes[(bytes[1] - 1) * 512 + 5] = 0x00
    end
    @test_throws C3D.IrrecoverableFormatError readc3d(nonamelength)

    # Setting both the POINT:DATA_START parameter and the header's DATA_START word (bytes
    # 17:18) to block 1 (the header itself) leaves no source for where the data section starts
    nodatastart = patchc3d(src) do bytes, c3d
        p = c3d.groups[:POINT].params[:DATA_START]
        # first data byte of a scalar parameter: after name length, gid, name, pointer (2
        # bytes), element size, and number of dimensions
        i = p.pos + 7 + length(p._name)
        bytes[i:i+1] .= (0x01, 0x00)
        bytes[17:18] .= (0x01, 0x00)
    end
    @test_throws C3D.IrrecoverableFormatError readc3d(nodatastart)

    # Two parameters with the same name and no group: SUBJECT:WEIGHT is renamed to HEIGHT
    # (same length), and both are moved to the undefined group 20
    dupnames = patchc3d(src) do bytes, c3d
        S = c3d.groups[:SUBJECT].params
        bytes[S[:WEIGHT].pos .+ (3:8)] .= codeunits("HEIGHT")
        bytes[S[:WEIGHT].pos + 2] = 20
        bytes[S[:HEIGHT].pos + 2] = 20
    end
    @test_throws C3D.IrrecoverableFormatError readc3d(dupnames; paramsonly=true)
end
