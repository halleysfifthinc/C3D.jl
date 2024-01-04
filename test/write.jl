using C3D: _elsize, _ndims, _size

@testset "Writing" begin

    # Test that groups can read/write round-trip identically
    @testset "Groups" begin
        for fn in filter(contains(r".c3d$"), readdir(artifact"sample08"; join=true))
            f = readc3d(fn)
            gs = keys(f.groups)

            for g in gs
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
                expr = :(==(compare_parameters($f, :GROUP, :PARAMETER)))
                expr.args[2].args[3] = QuoteNode(g) # replace :GROUP with g
                expr.args[2].args[4] = QuoteNode(p)

                # eval so that the group and parameter symbols appear as literals for
                    # readability if the test fails
                @eval @test $expr
            end
        end
    end
end
