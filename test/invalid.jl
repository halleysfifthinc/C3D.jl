@testset "Invalid data points" begin
    basketball = @test_nowarn readc3d(joinpath(datadir, "sample16", "basketball.c3d"))
    @test all(( all(v .=== missing) for (k,v) in basketball.point))
    basketball = @test_nowarn readc3d(joinpath(datadir, "sample16", "basketball.c3d"), missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in basketball.point))

    giant = @test_nowarn readc3d(joinpath(datadir, "sample16", "giant.c3d"))
    @test all(( all(v .=== missing) for (k,v) in giant.point))
    giant = @test_nowarn readc3d(joinpath(datadir, "sample16", "giant.c3d"), missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in giant.point))

    golf = @test_nowarn readc3d(joinpath(datadir, "sample16", "golf.c3d"))
    @test all(( all(v .=== missing) for (k,v) in golf.point))
    golf = @test_nowarn readc3d(joinpath(datadir, "sample16", "golf.c3d"), missingpoints=false)
    @test !any(( any(v .=== missing) for (k,v) in golf.point))
end
