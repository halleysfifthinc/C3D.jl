struct Header{END<:AbstractEndian}
    paramptr::UInt8 # Pointer to the first block of the parameter section
    datafmt::UInt8 # Data section storage format (0x50 == XYZ)
    npoints::UInt16 # Number of points/markers
    ampf::UInt16 # Total number of analog samples per point frame
    fframe::UInt16 # First frame number of raw data
    lframe::UInt16 # Last frame number of raw data
    maxinterp::UInt16 # Longest gap fill
    scale::Float32 # Factor that scales raw data to correct 3D units (mm)
    datastart::UInt16 # Pointer to the first block of the data section
    aspf::UInt16 # Analog sampling rate per point frame (eg analog Hz per point Hz)
    pointrate::Float32 # Frame rate of 3D point data
    res1::Vector{UInt8} # Unused/reserved (274 bytes); must be replicated when files are edited/written
    labeltype::UInt16 # Magic number of event label formats
    numevents::UInt16 # The number of events in the header
    res2::UInt16 # Unused/reserved; must be replicated when files are edited/written
    evtimes::NTuple{18,Float32} # Event times
    evstat::NTuple{18,UInt8} # Event status ON (0x01) or OFF (0x00)
    res3::UInt16 # Unused/reserved; must be replicated when files are edited/written
    evlabels::NTuple{36,UInt16} # Event labels
    res4::NTuple{11,UInt32} # Unused/reserved; must be replicated when files are edited/written
end

function Base.read(f::IOStream, ::Type{Header{END}}) where {END<:AbstractEndian}
    m = position(f)
    seekstart(f)
    io = IOBuffer(read(f, 512))
    seek(f, m)

    seekstart(io)
    paramptr = read(io, UInt8)
    datafmt = read(io, UInt8)
    npoints = read(io, END(UInt16))
    ampf = read(io, END(UInt16))
    fframe = read(io, END(UInt16))
    lframe = read(io, END(UInt16))
    maxinterp = read(io, END(UInt16))
    scale = read(io, END)
    datastart = read(io, END(UInt16))
    aspf = read(io, END(UInt16))
    pointrate = read(io, END)
    res1 = Vector{UInt8}(undef, 274)
    read!(io, res1)

    labeltype = read(io, END(UInt16))
    numevents = read(io, END(UInt16))

    res2 = read(io, END(UInt16))

    evtimes = ntuple(i -> read(io, END), 18)
    evstat = ntuple(i -> read(io, END(UInt8)), 18)

    res3 = read(io, UInt16)

    evlabels = ntuple(i -> read(io, END(UInt16)), 36)
    res4 = ntuple(i -> read(io, END(UInt32)), 11)

    # tdata = convert.(Char, read!(io, Array{UInt8}(undef, (4, 18))))
    # eventlabels = [ Symbol(replace(strip(String(@view(tdata[((i - 1) * 4 + 1):(i * 4)]))),
    #                                r"[^a-zA-Z0-9_]" => '_')) for i in 1:18]


    # events = Dict{Symbol,Array{Float32,1}}(( ev => Float32[]
    #             for ev in unique(eventlabels[validevents])))
    # for (event, time) in zip(eventlabels[validevents], eventtimes[validevents])
    #     push!(events[event], time)
    # end

    return Header{END}(paramptr, datafmt, npoints, ampf, fframe, lframe, maxinterp, scale,
                     datastart, aspf, pointrate, res1, labeltype, numevents, res2, evtimes,
                     evstat, res3, evlabels, res4)
end

function Base.write(io::IO, h::Header{END}) where {END<:AbstractEndian}
    EWORD = END(UInt16)
    nb = write(io, h.paramptr)
    nb += write(io, h.datafmt)
    nb += write(io, EWORD(h.npoints))
    nb += write(io, EWORD(h.ampf))
    nb += write(io, EWORD(h.fframe))
    nb += write(io, EWORD(h.lframe))
    nb += write(io, EWORD(h.maxinterp))
    nb += write(io, END(h.scale))
    nb += write(io, EWORD(h.datastart))
    nb += write(io, EWORD(h.aspf))
    nb += write(io, END(h.pointrate))
    nb += write(io, h.res1)
    nb += write(io, EWORD(h.labeltype))
    nb += write(io, EWORD(h.numevents))
    nb += write(io, EWORD(h.res2))
    nb += sum(x -> write(io, END(x)), h.evtimes)
    nb += write(io, collect(h.evstat))
    nb += write(io, EWORD(h.res3))
    nb += sum(x -> write(io, EWORD(x)), h.evlabels)
    nb += sum(x -> write(io, END(UInt32)(x)), h.res4)

    return nb
end

