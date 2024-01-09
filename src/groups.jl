# Group format description https://www.c3d.org/HTML/Documents/groupformat1.htm
mutable struct Group{END<:AbstractEndian}
    const pos::Int
    gid::Int8 # Group ID
    const locked::Bool
    const _name::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    const name::Symbol
    const np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    const _desc::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    const params::Dict{Symbol,Parameter}
end

function Group(
    pos::Int, gid::Int8, locked::Bool, _name::Vector{UInt8}, name::Symbol, np::Int16,
    _desc::Vector{UInt8}, params::Dict{Symbol,Parameter}
)
    return Group{LE{Float32}}(pos, gid, locked, _name, name, np, _desc, params)
end

function Group{END}(
    pos, gid, locked, name, np, desc, params=Dict{Symbol,Parameter}()
) where {END<:AbstractEndian}
    return Group{END}(pos, convert(Int8, gid), locked, Vector{UInt8}(name), Symbol(name),
        convert(Int16, np), Vector{UInt8}(desc), params)
end

function Group(pos, gid, locked, name, np, desc, params=Dict{Symbol,Parameter}())
    return Group{LE{Float32}}(pos, convert(Int8, gid), locked, Vector{UInt8}(name),
        Symbol(name), convert(Int16, np), Vector{UInt8}(desc), params)
end

function Group{END}(
    name::String, desc::String, params=Dict{Symbol,Parameter}(); gid=0, locked=signbit(gid)
) where {END<:AbstractEndian}
    return Group{END}(0, gid, locked, name, 0, desc, params)
end

function Group(name::String, desc::String, params=Dict{Symbol,Parameter}(); gid=0, locked=signbit(gid))
    return Group{LE{Float32}}(0, gid, locked, name, 0, desc, params)
end

function Base.getindex(g::Group, k::Symbol)
    return getindex(g.params, k).payload.data
end

function Base.getindex(g::Group, ::Type{T}, k::Symbol) where T
    return typedindex(g, T, k)
end

function typedindex(g::Group, ::Type{Vector{T}}, k) where T
    local r::Vector{T}
    if typeof(g[k]) <: Vector
        r = g[k]
    else
        r = T[g[k]]
    end

    return r
end

function typedindex(g::Group, ::Type{T}, k) where T
    r::T = g[k]
    return r
end

Base.keys(g::Group) = keys(g.params)
Base.values(g::Group) = values(g.params)
Base.haskey(g::Group, key) = haskey(g.params, key)

# TODO: Add get! method?
function Base.get(g::Group, key, default)
    _key = key isa Tuple ? last(key) : key
    return haskey(g, _key) ? g[key...] : default
end

Base.show(io::IO, g::Group) = show(io, keys(g.params))

function Base.read(io::IO, ::Type{Group{END}}) where {END<:AbstractEndian}
    pos = position(io)
    nl = read(io, Int8)
    @assert nl != 0
    locked = signbit(nl)
    gid = read(io, Int8)
    @assert gid != 0
    _name = read(io, abs(nl))
    @assert any(!iscntrl∘Char, _name)
    name = Symbol(replace(strip(transcode(String, copy(_name))), r"[^a-zA-Z0-9_]" => '_'))

    @debug "Group $name at $pos has unofficially supported characters.
        Unexpected results may occur" maxlog=occursin(r"[^a-zA-Z0-9_ ]", transcode(String, copy(_name)))

    np = read(io, END(Int16))

    dl = read(io, UInt8)
    desc = read(io, dl)

    pointer = pos + np + abs(nl) + 2
    @debug "wrong pointer in $name" position(io), pointer maxlog=(position(io) != pointer)
    return Group{END}(pos, gid, locked, _name, name, np, desc, Dict{Symbol,Parameter}())
end

function Base.write(io::IO, g::Group{END}; last::Bool=false) where {END}
    nb = 0
    nb += write(io, flipsign(UInt8(length(g._name)), -1*g.locked))
    nb += write(io, g.gid)
    nb += write(io, g._name)
    nb += write(io, last ? 0x0000 : END(Int16)(UInt16(length(g._desc) + 3)))
    nb += write(io, UInt8(length(g._desc)))
    if !isempty(g._desc)
        nb += write(io, g._desc)
    end

    return nb
end

function writesize(g::Group{END}) where {END}
    return 5 + length(g._name) + length(g._desc)
end

