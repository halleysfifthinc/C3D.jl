struct C3DHeader
    paramptr::Int8
    npoints::Int16
    ampf::Int16
    fframe::Int16
    lframe::Int16
    maxinterp::Int16
    scale::Float32
    datastart::Int16
    aspf::Int16
    pointrate::Float32
    res1::Array{UInt8,1}
    labelrange::Union{UInt16,Nothing}
    res2::UInt16
    events::Dict{Symbol,Array{Float32,1}}
    res3::UInt16
end

function readheader(f::IOStream, FEND::Endian, FType::Type{T}) where T <: Union{Float32,VaxFloatF}
    seek(f,0)
    paramptr = read(f, Int8)
    read(f, Int8)
    npoints = saferead(f, Int16, FEND)
    ampf = saferead(f, Int16, FEND)
    fframe = saferead(f, Int16, FEND)
    lframe = saferead(f, Int16, FEND)
    maxinterp = saferead(f, Int16, FEND)
    scale = saferead(f, FType, FEND)
    datastart = saferead(f, Int16, FEND)
    aspf = saferead(f, Int16, FEND)
    pointrate = saferead(f, FType, FEND)
    res1 = read(f, 137*2)

    tmp = saferead(f, Int16, FEND)
    tmp_lr = saferead(f, Int16, FEND)
    labelrange = (tmp == 0x3039) ? tmp_lr : nothing

    char4 = (saferead(f, Int16, FEND) == 0x3039)
    skip(f, 2)
    res2 = read(f, UInt16)

    eventtimes = saferead(f, FType, FEND, 18)
    eventflags = read!(f, Array{Bool}(undef, 18))
    validevents = findall(iszero, eventflags) 

    res3 = read(f, UInt16)

    tdata = convert.(Char, read!(f, Array{UInt8}(undef, (4, 18))))
    eventlabels = [ Symbol(replace(strip(String(@view(tdata[((i - 1) * 4 + 1):(i * 4)]))),
                                   r"[^a-zA-Z0-9_]" => '_')) for i in 1:18]


    events = Dict{Symbol,Array{Float32,1}}(( ev => Float32[]
                for ev in unique(eventlabels[validevents])))
    for (event, time) in zip(eventlabels[validevents], eventtimes[validevents])
        push!(events[event], time)
    end

    return C3DHeader(paramptr, npoints, ampf, fframe, lframe, maxinterp, scale,
                     datastart, aspf, pointrate, res1, labelrange, res2, events, res3)
end

