@testset "Corrupted/incorrect files" begin
    @test_nothrow readc3d(artifact"sample18/bad_parameter_section.c3d")
    @test_nothrow readc3d(artifact"sample27/kyowadengyo.c3d")
end

@testset "Incorrectly formatted residuals" begin
    # Biogesta Saga-3RT@v1.0.4
    @test_logs (:warn,r"residuals") readc3d(artifact"sample30/marche281.c3d")

    # Biogesta Saga-3RT@v1.4.1
    @test_logs (:warn,r"residuals") readc3d(artifact"sample30/admarche2.c3d")
end
