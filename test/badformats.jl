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
    @test_throws C3D.IrrecoverableFormatError "Found 0x57" readc3d(badproc)

    # The parameter section pointer (byte 1) is a 1-based block number, and block 1 is the
    # header, so 0 and 1 can't point to a parameter section
    noparams = patchc3d(src) do bytes, c3d
        bytes[1] = 0x00
    end
    @test_throws C3D.IrrecoverableFormatError "parameter section pointer" readc3d(noparams)

    # We cannot successfully read a file if the first record is invalid. The first record
    # starts at byte 5 of the parameter section, with its name length (Int8; negative means
    # locked, so 0 and -128 are the invalid values)
    nonamelength = patchc3d(src) do bytes, c3d
        bytes[(bytes[1] - 1) * 512 + 5] = 0x00
    end
    @test_throws C3D.IrrecoverableFormatError "no valid group or parameter records" readc3d(nonamelength)
    longnamelength = patchc3d(src) do bytes, c3d
        bytes[(bytes[1] - 1) * 512 + 5] = 0x80
    end
    @test_throws C3D.IrrecoverableFormatError "no valid group or parameter records" readc3d(longnamelength)

    # Writes `block` to the POINT:DATA_START parameter and `hblock` to the header's
    # DATA_START word (bytes 17:18)
    patchdatastart(block, hblock) = patchc3d(src) do bytes, c3d
        p = c3d.groups[:POINT].params[:DATA_START]
        # first data byte of a scalar parameter: after name length, gid, name, pointer (2
        # bytes), element size, and number of dimensions
        i = p.pos + 7 + length(p._name)
        bytes[i:i+1] .= (block, 0x00)
        bytes[17:18] .= (hblock, 0x00)
    end

    # A POINT:DATA_START of 0 (missing) falls back to the header. `validate=false`, because
    # `validatec3d` also replaces a POINT:DATA_START of 0 with the header's value
    zerodatastart = patchdatastart(0x00, 0x0b)
    @test isequal(readc3d(zerodatastart; validate=false).point,
        readc3d(src; validate=false).point)

    # With neither DATA_START pointing past the header (block 1), there is no source for
    # where the data section starts
    @test_throws C3D.IrrecoverableFormatError "DATA_START" readc3d(patchdatastart(0x01, 0x01))
    @test_throws C3D.IrrecoverableFormatError "DATA_START" readc3d(patchdatastart(0x00, 0x00))

    # Two parameters with the same name and no group: SUBJECT:WEIGHT is renamed to HEIGHT
    # (same length), and both are moved to the undefined group 20
    dupnames = patchc3d(src) do bytes, c3d
        S = c3d.groups[:SUBJECT].params
        bytes[S[:WEIGHT].pos .+ (3:8)] .= codeunits("HEIGHT")
        bytes[S[:WEIGHT].pos + 2] = 20
        bytes[S[:HEIGHT].pos + 2] = 20
    end
    @test_throws C3D.IrrecoverableFormatError "undefined group ID 20 have duplicate names" readc3d(dupnames; paramsonly=true)
end
