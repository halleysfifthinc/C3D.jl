@testset "Inference" begin
f = readc3d(artifact"sample01/Eb015pr.c3d")

@test @inferred(f.groups[:ANALOG][Vector{Int16}, :OFFSET]) == fill(Int16(2048), 32)
@test @inferred(f.groups[:ANALOG][Int16, :USED]) == 16

# Test implicit conversion
@test @inferred(f.groups[:ANALOG][Int, :USED]) == 16
@test @inferred(f.groups[:ANALOG][Vector{Int}, :OFFSET]) == fill(2048, 32)
end

