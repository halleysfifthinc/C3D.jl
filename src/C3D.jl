module C3D

include("vaxtype.jl")

export readc3d

# Group format description https://www.c3d.org/HTML/groupformat1.htm
mutable struct Group
    nl::Int8 # Number of characters in group name (nominally should be between 1 and 127)
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    dl::Int8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
end

Base.show(io::IO, g::Group) = print(io, "Group{\"",g.name,"\"}:\n ", g.desc)

# Parameter format description https://www.c3d.org/HTML/parameterformat1.htm
mutable struct Parameter
    nl::UInt8 # Number of characters in group name (nominally should be between 1 and 127)
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data

    # Array format description https://www.c3d.org/HTML/parameterarrays1.htm
    nd::Int8
    # dims::NTuple{convert(nd),Int8} # Vector of bytes describing array dimensions
    # data::Array{Int,convert(nd)}(dims)
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
end

relseek(s::IOStream, n::Int) = seek(s, position(s) + n)

function readgroup(f::IOStream)

    nl = read(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = read(f, Int8)
    name = transcode(String, read(f, nl))
    np = read(f, Int16)
    dl = read(f, Int8)
    desc = transcode(String, read(f, dl))

    return Group(nl, isLocked, gid, name, np, dl, desc)

end

function readc3d(filename::AbstractString)
    if !isfile(filename)
        error("File ", filename, " cannot be found")
    end
    
    file = open(filename, "r")

    params_ptr = read(file, UInt8)
    
    if read(file, UInt8) != 0x50
        error("File ", filename, " is not a valid C3D file")
    end

    # Jump to parameters block
    seek(file, (params_ptr - 1) * 512)

    # Skip 2 reserved bytes 
    read(file, UInt16)

    paramblocks = read(file, UInt8)
    proctype = read(file, UInt8) - 83

    # Deal with host big-endianness in the future
    if proctype == 1
        # little-endian
    elseif proctype == 2
        # DEC floats; little-endian
        error("DEC processor type files not supported yet")
    elseif proctype == 3
        # big-endian
        error("SGI/MIPS processor type files not supported yet")
    else
        error("Malformed processor type. Expected 1, 2, or 3. Found ", proctype)
    end

    read(file, UInt8)
    if read(file, Int8) < 0
        # Group
        relseek(file, -2)
        group1 = readgroup(file)
    else
        # Parameter
        error("Its a parameter")
    end

    close(file)

    return group1
end

end # module
