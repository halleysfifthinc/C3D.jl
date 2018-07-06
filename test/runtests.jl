using C3D, Test

datadir = joinpath(@__DIR__,"..","data")

include("identical.jl")
include("bigdata.jl")
include("singledata.jl")
include("invalid.jl")

