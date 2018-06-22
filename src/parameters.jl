# Parameter format description https://www.c3d.org/HTML/parameterformat1.htm
struct Parameter{T,N} <: AbstractArray{T,N}
    pos::Int
    nl::Int8 # Number of characters in group name
    isLocked::Bool # Locked if nl < 0
    gid::Int8 # Group ID
    name::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
    symname::Symbol
    np::Int16 # Pointer in bytes to the start of next group/parameter (officially supposed to be signed)
    ellen::Int8
    # -1 => Char data
    #  1 => Byte data
    #  2 => Int16 data
    #  4 => Float data

    # Array format description https://www.c3d.org/HTML/parameterarrays1.htm
    nd::Int8
    dims::Tuple # Vector of bytes (Int8 technically) describing array dimensions
    data::Array{T,N}
    dl::UInt8 # Number of characters in group description (nominally should be between 1 and 127)
    desc::String # Character set should be A-Z, 0-9, and _ (lowercase is ok)
end

Base.getindex(p::Parameter, i...) = getindex(p.data, i...)
Base.size(p::Parameter) = size(p.data)


function readparam(f::IOStream, FEND::Endian, FType::Type{Y}) where Y <: Union{Float32,VaxFloatF}
    pos = position(f)
    nl = read(f, Int8)
    isLocked = nl < 0 ? true : false
    gid = read(f, Int8)
    name = transcode(String, read(f, abs(nl)))
    symname = Symbol(replace(strip(name), r"[^a-zA-Z0-9_]" => '_'))

    if occursin(r"[^a-zA-Z0-9_ ]", name)
        warn("Parameter ", name, " has unofficially supported characters.
            Unexpected results may occur")
    end

    np = saferead(f, Int16, FEND)

    ellen = read(f, Int8)
    if ellen == -1
        T = TA = String
    elseif ellen == 1
        T = TA = Int8
    elseif ellen == 2
        T = TA = Int16
    elseif ellen == 4
        T = FType
        TA = Float32
    else
        println("File position in bytes ", position(f))
        println("nl: ", nl, "\ngid: ", gid, "\nname: ", name, "\nnp: ", np, "\nellen: ", ellen)
        error("Invalid parameter element type. Found ", ellen)
    end

    nd = read(f, Int8)
    if nd > 0
        dims = NTuple{convert(Int, nd),Int}(read!(f, Array{Int8}(undef, nd)))
        if T == String
            tdata = convert.(Char, read!(f, Array{UInt8}(undef, dims)))
            if nd > 1
                data = [ String(@view(tdata[((i - 1) * dims[1] + 1):(i * dims[1])])) for i in 1:(*)(dims[2:end]...)]
            else
                data = [ String(tdata) ]
            end
        else
            data = saferead(f, T, FEND, dims)
        end
    else
        dims = ()
        if T == String
            data = [ convert(Char, read(f, UInt8)) ]
        else
            data = [ saferead(f, T, FEND) ]
        end
    end

    dl = read(f, UInt8)
    desc = transcode(String, read(f, dl))

    N = (nd == 0) ? 1 : convert(Int, nd)

    if T == String && N > 1
        N -= 1
    end

    return Parameter{TA,N}(pos, nl, isLocked, gid, name, symname, np, ellen, nd, dims, data,
            dl, desc)
end