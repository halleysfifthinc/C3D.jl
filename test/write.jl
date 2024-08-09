using C3D: _elsize, _ndims, _size, writesize

function compare_header_write(fn)
    ref = open(fn) do io
        read(io, 512)
    end;
    f = readc3d(fn; paramsonly=true)

    io = IOBuffer()
    write(io, f.header);
    comp = take!(io);

    return ref, comp
end

@testset "Writing" begin
    artifacts = keys(parsefile(find_artifacts_toml(@__FILE__)))
    # Test that headers can read/write round-trip identically
    @testset "Headers" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        # Those files are incomplete (end is cut off)
        art == "sample13" && basename(fn) in ("Dance.c3d", "golfswing.c3d") &&
            continue

        ref, comp = compare_header_write(fn)
        @test ref == comp
    end
    end
    end

    # Test that groups can read/write round-trip identically
    @testset "Groups" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        f = readc3d(fn; paramsonly=true)
        gs = keys(f.groups)

        for g in gs
            @test write(IOBuffer(), f.groups[g]) == writesize(f.groups[g])
            @test ==(compare_parameters(f, g))
        end
    end
    end
    end

    # Test that parameters can read/write round-trip identically (trimmed white-space is
    # ignored)
    @testset "Parameters:" begin
    @testset "artifact\"$art\"" for art in artifacts
        allfiles = filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
    @testset "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in allfiles
        f = readc3d(fn; paramsonly=true)
        fio = open(fn)
        gs = keys(f.groups)
        ps = [ (g,p) for g in gs for p in keys(f.groups[g].params) ]

        for (g,p) in ps
            @test write(IOBuffer(), f.groups[g].params[p], endianness(f)) == writesize(f.groups[g].params[p])

            # :GROUP and :PARAMETER are placeholders that are replaced with the actual
            # group and parameter names
            expr = :(==(compare_parameters($f, :GROUP, :PARAMETER)))
            expr.args[2].args[3] = QuoteNode(g) # replace :GROUP with g
            expr.args[2].args[4] = QuoteNode(p) # same for :PARAMETER

            # eval so that the group and parameter symbols appear as literals for
                # readability if the test fails
            @eval @test $expr
        end
    end
    end
    end

    @testset "Whole file: artifact\"$art\"" for art in ["sample01"]#, "sample02", "sample08"]
        @testset failfast=true "File \"$(replace(fn, @artifact_str(art)*'/' => ""))\"" for fn in filter(contains(r".c3d$"i), readdir_recursive(@artifact_str(art); join=true))
            p, io = mktemp()
            writec3d(io, readc3d(fn))
            flush(io)
            close(io)
            comparefiles(fn, p)
        end
    end
end
