# Group format description https://www.c3d.org/HTML/groupformat1.htm
struct Group
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    params::Dict{Symbol,AbstractParameter}
end

function Base.getproperty(g::Group, name::Symbol)
    if name ∈ fieldnames(typeof(g))
        return getfield(g, name)
    else
        return getfield(g, :params)[name].data
    end
end
Base.show(io::IO, g::Group) = show(io, keys(g.params))

function readgroup(f::IOStream, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    pos = position(f)
    nl = read(f, Int8)
    @assert nl != 0
    isLocked = nl < 0 ? true : false
    gid = read(f, Int8)
    @assert gid != 0
    name = transcode(String, read(f, abs(nl)))
    @assert any(!iscntrl, name)
    symname = Symbol(replace(strip(name), r"[^a-zA-Z0-9_]" => '_'))

    if occursin(r"[^a-zA-Z0-9_ ]", name)
        @debug "Group $name at $pos has unofficially supported characters.
            Unexpected results may occur"
    end

    np = saferead(f, Int16, FEND)
    dl = read(f, UInt8)
    desc = transcode(String, read(f, dl))

    return Group(pos, nl, isLocked, gid, name, symname, np, dl, desc, Dict{Symbol,AbstractParameter}())
end

