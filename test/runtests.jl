using C3D
using Compat.Test

datadir = joinpath(@__DIR__,"..","data")

include("identical.jl")
include("bigdata.jl")
include("singledata.jl")

