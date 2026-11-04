# JET is not run on Julia prereleases (JET generally does not support them)
@testitem "JET" skip=!isempty(VERSION.prerelease) begin
    using JET
    JET.func_test(
        function (args...; jetconfigs...)
            result = report_package(args...; jetconfigs...)
            filter!(result.res.inference_error_reports) do report
                !(report isa JET.UndefVarErrorReport && report.maybeundef)
            end
            result
        end, :test_package, C3D; target_modules=(C3D,), toplevel_logger=nothing)
end

@testitem "Type-stable parameter access" begin
    using LazyArtifacts
    f = readc3d(artifact"sample01/Eb015pr.c3d")

    @test @inferred(f.groups[:ANALOG][Vector{Int16}, :OFFSET]) == fill(Int16(2048), 32)
    @test @inferred(f.groups[:ANALOG][Int16, :USED]) == 16

    # Test implicit conversion
    @test @inferred(f.groups[:ANALOG][Int, :USED]) == 16
    @test @inferred(f.groups[:ANALOG][Vector{Int}, :OFFSET]) == fill(2048, 32)
end
