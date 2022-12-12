@testset "empty LABELS" begin
    @test readc3d(joinpath(artifact"sample24", "MotionMonitorC3D.c3d")) isa C3DFile
    f = readc3d(joinpath(artifact"sample24", "MotionMonitorC3D.c3d"))
    @test !any(isempty.(collect(keys(f.point))))
    @test !any(isempty.(collect(keys(f.analog))))
end
