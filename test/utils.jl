@testset "TRC" begin
    mktemp() do path, io
        @test writetrc(path, readc3d(artifact"sample01/Eb015pr.c3d")) == nothing
    end
    mktemp() do path, io
        f = readc3d(artifact"sample01/Eb015pr.c3d")
        @test writetrc(path, f; virtual_markers=Dict("TEST1" => similar(f.point[first(keys(f.point))]))) == nothing
    end

    f = readc3d(artifact"sample03/gait-pig.c3d")
    mktemp() do path, io
        @test writetrc(path, f; strip_prefixes=false, remove_unlabeled_markers=false) == nothing
    end
    mktemp() do path, io
        @test writetrc(path, f; subject="A22", strip_prefixes=false, remove_unlabeled_markers=false) == nothing
    end
    mktemp() do path, io
        @test writetrc(path, f; strip_prefixes=true, remove_unlabeled_markers=false) == nothing
    end
    mktemp() do path, io
        @test writetrc(path, f; strip_prefixes=true, remove_unlabeled_markers=true) == nothing
    end

    f = readc3d(artifact"sample03/gait-pig-nz.c3d") # Contains unlabeled markers
    mktemp() do path, io
        @test writetrc(path, f; strip_prefixes=true, remove_unlabeled_markers=false) == nothing
    end
    mktemp() do path, io
        @test writetrc(path, f; strip_prefixes=true, remove_unlabeled_markers=true) == nothing
    end
end
