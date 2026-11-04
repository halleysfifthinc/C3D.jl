@testitem "Aqua tests" begin
    using Aqua
    Aqua.test_all(C3D)
end

@testitem "Explicit and public imports" begin
    using ExplicitImports
    @test check_no_implicit_imports(C3D) === nothing
    @test check_no_stale_explicit_imports(C3D) === nothing
    @test check_all_explicit_imports_via_owners(C3D) === nothing
    @test check_all_qualified_accesses_are_public(C3D;
        ignore=(
            :CompoundPeriod, :value, # Dates
            :filter, :format_bytes, :_setindex!, :ht_keyindex2_shorthash!, # Base/Iterators
            :add_new! # OrderedCollections
        )) === nothing
end
