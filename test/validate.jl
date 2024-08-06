@testset "Validation" begin
    let
        path, _io = mktemp()
        write(_io, zeros(UInt8, 10))
        seekstart(_io)
        @test_throws r"not a valid C3D file" C3D._readparams(_io, :drop)
        close(_io)
    end

    using C3D: validatec3d, MissingParametersError, MissingGroupsError
    f = readc3d(artifact"sample01/Eb015pr.c3d")

    @test_nothrow readc3d(artifact"sample28/dynamic.C3D")
    @test_nothrow readc3d(artifact"sample28/standing.C3D")
    @test_nothrow readc3d(artifact"sample28/type1.C3D")
    # @testset "Custom errors" begin
    #     @test_nowarn MissingGroupsError(:hello)
    #     @test_nowarn MissingGroupsError((:hello,:world))
    #     @test_nowarn MissingGroupsError([:hello,:world])

    #     @test sprint(showerror, MissingGroupsError(:POINT)) ==
    #         "Required group(s) :POINT are missing"

    #     @test_nowarn MissingParametersError(:POINT, :USED)
    #     @test_nowarn MissingParametersError(:POINT, (:hello,:world))
    #     @test_nowarn MissingParametersError(:POINT, [:hello,:world])

    #     @test sprint(showerror, MissingParametersError(:POINT, :USED)) ==
    #         "Group :POINT is missing required parameter(s) :USED"
    # end

    # @testset "Missing parameters" begin
    #     bad_groups = deepcopy(groups)
    #     delete!(bad_groups[:POINT].params, :USED)
    #     @test_throws MissingParametersError validatec3d(header, bad_groups)

    #     bad_groups = deepcopy(groups)
    #     delete!(bad_groups[:ANALOG].params, :USED)
    #     @test_throws MissingParametersError validatec3d(header, bad_groups)
    # end
end
