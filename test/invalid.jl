@testset "Invalid data points" begin
    @test_nothrow readc3d(artifact"sample16/basketball.c3d")
    basketball = readc3d(artifact"sample16/basketball.c3d")
    @test all(( all(v .=== missing) for (k,v) in basketball.point))

    @test_nothrow readc3d(artifact"sample16/basketball.c3d", missingpoints=false)
    basketball = readc3d(artifact"sample16/basketball.c3d", missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in basketball.point))

    @test_nothrow readc3d(artifact"sample16/giant.c3d")
    giant = readc3d(artifact"sample16/giant.c3d")
    @test all(( all(v .=== missing) for (k,v) in giant.point))

    @test_nothrow readc3d(artifact"sample16/giant.c3d", missingpoints=false)
    giant = readc3d(artifact"sample16/giant.c3d", missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in giant.point))

    @test_nothrow readc3d(artifact"sample16/golf.c3d")
    golf = readc3d(artifact"sample16/golf.c3d")
    @test all(( all(v .=== missing) for (k,v) in golf.point))

    @test_nothrow readc3d(artifact"sample16/golf.c3d", missingpoints=false)
    golf = readc3d(artifact"sample16/golf.c3d", missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in golf.point))
end
