using C3D, Test

cd(@__DIR__)
datadir = joinpath("..", "data")

include("identical.jl")
include("bigdata.jl")
include("singledata.jl")
include("invalid.jl")
include("blanklabels.jl")
include("badformats.jl")

