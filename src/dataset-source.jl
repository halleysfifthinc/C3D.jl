using .DatasetManager

export C3DSource

struct C3DSource <: AbstractSource
    path::String
end

function DatasetManager.readsource(s::C3DSource; kwargs...)
    return readc3d(sourcepath(s); kwargs...)
end

