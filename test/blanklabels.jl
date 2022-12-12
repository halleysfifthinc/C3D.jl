@testset "empty LABELS" begin
    f = @test_nowarn readc3d(joinpath(artifact"sample24", "MotionMonitorC3D.c3d"))
    @test !any(isempty.(collect(keys(f.point))))
    @test !any(isempty.(collect(keys(f.analog))))
end
