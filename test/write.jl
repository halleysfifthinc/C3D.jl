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
    # Test that headers can read/write round-trip identically
    @testset "Headers" begin
        for art in keys(parsefile(find_artifacts_toml(@__FILE__)))
            @testset "Artifact: $art" begin
                for fn in filter(contains(r".c3d$"), readdir(@artifact_str(art); join=true))
                    # Those files are incomplete (end is cut off)
                    art == "sample13" && basename(fn) in ("Dance.c3d", "golfswing.c3d") &&
                        continue
                    ref, comp = compare_header_write(fn)
                    @test ref == comp
                end
            end
        end
    end

    # Test that groups can read/write round-trip identically
    @testset "Groups" begin
        for fn in filter(contains(r".c3d$"), readdir(artifact"sample08"; join=true))
            f = readc3d(fn)
            gs = keys(f.groups)

            for g in gs
                @test write(IOBuffer(), f.groups[g]) == writesize(f.groups[g])
                @test ==(compare_parameters(f, g))
            end
        end
    end

    # Test that parameters can read/write round-trip identically (trimmed white-space is
    # ignored)
    @testset "Parameters" begin
        for fn in filter(contains(r".c3d$"), readdir(artifact"sample08"; join=true))
            f = readc3d(fn)
            fio = open(fn)
            gs = keys(f.groups)
            ps = [ (g,p) for g in gs for p in keys(f.groups[g].params) ]

            for (g,p) in ps
                @test write(IOBuffer(), f.groups[g].params[p], endianness(f)) == writesize(f.groups[g].params[p])
                expr = :(==(compare_parameters($f, :GROUP, :PARAMETER)))
                expr.args[2].args[3] = QuoteNode(g) # replace :GROUP with g
                expr.args[2].args[4] = QuoteNode(p)

                # eval so that the group and parameter symbols appear as literals for
                    # readability if the test fails
                @eval @test $expr
            end
        end
    end

    @testset "Files" begin
        for art in ["sample01"]#, "sample02", "sample08"]
            @testset "Artifact: $art" begin
                for fn in filter(contains(r".c3d$"), readdir(@artifact_str(art); join=true))
                    p, io = mktemp()
                    writec3d(io, readc3d(fn))
                    flush(io)
                    close(io)
                    comparefiles(fn, p)
                end
            end
        end
    end
end
