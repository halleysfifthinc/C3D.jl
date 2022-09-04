@testset "Groups validation" begin
    using C3D: validatec3d, MissingParametersError
    f = readc3d(joinpath(datadir, "sample01/Eb015pr.c3d"))
    header, groups = f.header, f.groups

    @testset "Missing parameters" begin
        bad_groups = deepcopy(groups)
        delete!(bad_groups[:POINT].params, :USED)
        @test_throws MissingParametersError validatec3d(header, bad_groups)

        bad_groups = deepcopy(groups)
        delete!(bad_groups[:POINT].params, :RATE)
        @test_throws MissingParametersError validatec3d(header, bad_groups)

        bad_groups = deepcopy(groups)
        delete!(bad_groups[:ANALOG].params, :USED)
        @test_throws MissingParametersError validatec3d(header, bad_groups)
    end
end
