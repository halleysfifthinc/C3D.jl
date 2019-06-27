function comparefiles(reference, candidates)
    refc3d = @test_nowarn readc3d(reference; missingpoints=false)
    for candfn in candidates
        file = @test_nowarn readc3d(candfn; missingpoints=false)

        @testset "Parameters equivalency between files" begin
            @testset "Compare groups with $(file.name)" begin
                @test keys(file.groups) ⊆ keys(refc3d.groups)
            end
            for grp in keys(refc3d.groups)
                @testset "Compare :$(refc3d.groups[grp].symname) parameters with $(file.name)" begin
                    @test keys(file.groups[grp].params) ⊆ keys(refc3d.groups[grp].params)
                end
                @testset "Compare the :$(refc3d.groups[grp].symname) parameters" begin
                    for param in keys(refc3d.groups[grp].params)
                        if eltype(refc3d.groups[grp].params[param].data) <: Number
                            if grp == :POINT && param == :SCALE
                                @test abs.(refc3d.groups[grp].params[param].data) ≈ abs.(file.groups[grp].params[param].data)
                            elseif grp == :POINT && param == :DATA_START && any(basename(candfn) .== ("TESTBPI.c3d", "TESTCPI.c3d", "TESTDPI.c3d"))
                                @test file.groups[grp].params[param].data == 20
                            else
                                @test refc3d.groups[grp].params[param].data ≈ file.groups[grp].params[param].data
                            end
                        else
                            @test reduce(*,refc3d.groups[grp].params[param].data .== file.groups[grp].params[param].data)
                        end
                    end
                end
            end
        end

        @testset "Data equivalency between file types" begin
            @testset "Ensure data equivalency between $(refc3d.name) and $(file.name)" begin
                for sig in keys(refc3d.point)
                    @testset "$sig" begin
                        @test haskey(file.point,sig)
                        @test all(isapprox.(refc3d.point[sig], file.point[sig]; atol=0.3))
                    end
                end
                for sig in keys(refc3d.analog)
                    @testset "$sig" begin
                        @test haskey(file.analog,sig)
                        @test all(isapprox.(refc3d.analog[sig], file.analog[sig]; atol=0.3))
                    end
                end
            end
        end
    end
end

@testset "Comparing different files with identical data" begin
    sample01 = ( ("sample01", "Eb015pr.c3d"),
                 ("sample01", "Eb015pi.c3d"),
                 ("sample01", "Eb015vr.c3d"),
                 ("sample01", "Eb015vi.c3d"),
                 ("sample01", "Eb015sr.c3d"),
                 ("sample01", "Eb015si.c3d"))

    sample02 = ( ("sample02", "pc_real.c3d"),
                 ("sample02", "pc_int.c3d"),
                 ("sample02", "dec_real.c3d"),
                 ("sample02", "dec_int.c3d"),
                 ("sample02", "sgi_real.c3d"),
                 ("sample02", "sgi_int.c3d"))

    sample08 = ( ("sample08", "EB015PI.c3d"),
                 ("sample08", "TESTAPI.c3d"),
                 ("sample08", "TESTBPI.c3d"),
                 ("sample08", "TESTCPI.c3d"),
                 ("sample08", "TESTDPI.c3d"))

    @testset "sample01 files" begin
        comparefiles(joinpath(datadir, sample01[1]...), broadcast(x -> joinpath(datadir, x...), sample01[2:end]))
    end
    @testset "sample02 files" begin
        comparefiles(joinpath(datadir, sample02[1]...), broadcast(x -> joinpath(datadir, x...), sample02[2:end]))
    end
    @testset "sample08 files" begin
        comparefiles(joinpath(datadir, sample08[1]...), broadcast(x -> joinpath(datadir, x...), sample08[2:end]))
    end
end

