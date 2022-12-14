@testset "Invalid data points" begin
    @test readc3d(artifact"sample16/basketball.c3d") isa C3DFile
    basketball = readc3d(artifact"sample16/basketball.c3d")
    @test all(( all(v .=== missing) for (k,v) in basketball.point))
    @test readc3d(artifact"sample16/basketball.c3d", missingpoints=false) isa C3DFile
    basketball = readc3d(artifact"sample16/basketball.c3d", missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in basketball.point))

    @test readc3d(artifact"sample16/giant.c3d") isa C3DFile
    giant = readc3d(artifact"sample16/giant.c3d")
    @test all(( all(v .=== missing) for (k,v) in giant.point))
    @test readc3d(artifact"sample16/giant.c3d", missingpoints=false) isa C3DFile
    giant = readc3d(artifact"sample16/giant.c3d", missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in giant.point))

    @test readc3d(artifact"sample16/golf.c3d") isa C3DFile
    golf = readc3d(artifact"sample16/golf.c3d")
    @test all(( all(v .=== missing) for (k,v) in golf.point))
    @test readc3d(artifact"sample16/golf.c3d", missingpoints=false) isa C3DFile
    golf = readc3d(artifact"sample16/golf.c3d", missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in golf.point))
end
