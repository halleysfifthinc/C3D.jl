# Group format description https://www.c3d.org/HTML/Documents/groupformat1.htm
struct Group
    pos::Int
    gid::Int8 # Group ID
    locked::Bool
    _name::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    name::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    _desc::Vector{UInt8} # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    params::Dict{Symbol,Parameter}
end

function Group(pos, gid, locked, name, np, desc, params=Dict{Symbol,Parameter}())
    return Group(pos, convert(Int8, gid), locked, Vector{UInt8}(name), Symbol(name),
        convert(Int16, np), Vector{UInt8}(desc), params)
end

function Group(name::String, desc::String, params=Dict{Symbol,Parameter}(); gid=0, locked=signbit(gid))
    return Group(0, gid, locked, name, 0, desc, params)
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
Base.haskey(g::Group, key) = haskey(g.params, key)

# TODO: Add get! method?
function Base.get(g::Group, key, default)
    _key = key isa Tuple ? last(key) : key
    return haskey(g, _key) ? g[key...] : default
end

Base.show(io::IO, g::Group) = show(io, keys(g.params))

function readgroup(f::IOStream, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    pos = position(f)
    nl = read(f, Int8)
    @assert nl != 0
    locked = signbit(nl)
    gid = read(f, Int8)
    @assert gid != 0
    _name = read(f, abs(nl))
    @assert any(!iscntrl∘Char, _name)
    name = Symbol(replace(strip(transcode(String, copy(_name))), r"[^a-zA-Z0-9_]" => '_'))

    # if occursin(r"[^a-zA-Z0-9_ ]", name)
    #     @debug "Group $name at $pos has unofficially supported characters.
    #         Unexpected results may occur"
    # end

    np = saferead(f, Int16, FEND)
    dl = read(f, UInt8)
    desc = read(f, dl)
    return Group(pos, gid, locked, _name, name, np, desc, Dict{Symbol,Parameter}())
end

