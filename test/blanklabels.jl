@testset "empty LABELS" begin
    @test_nothrow readc3d(artifact"sample24/MotionMonitorC3D.c3d")
    f = readc3d(artifact"sample24/MotionMonitorC3D.c3d")
    @test_internalconsistency f
    @test !any(isempty.(collect(keys(f.point))))
    @test !any(isempty.(collect(keys(f.analog))))
end
