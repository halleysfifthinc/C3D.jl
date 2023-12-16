struct Header{END<:AbstractEndian}
    paramptr::UInt8
    npoints::UInt16
    ampf::UInt16
    fframe::UInt16
    lframe::UInt16
    maxinterp::UInt16
    scale::Float32
    datastart::UInt16
    aspf::UInt16
    pointrate::Float32
    res1::Array{UInt8,1}
    labelrange::Union{UInt16,Nothing}
    res2::UInt16
    events::Dict{Symbol,Array{Float32,1}}
    res3::UInt16
end

function Base.read(f::IOStream, ::Type{Header{END}}) where {END<:AbstractEndian}
    seek(f,0)
    paramptr = read(f, UInt8)
    read(f, Int8)
    npoints = read(f, END(UInt16))
    ampf = read(f, END(UInt16))
    fframe = read(f, END(UInt16))
    lframe = read(f, END(UInt16))
    maxinterp = read(f, END(UInt16))
    scale = read(f, END)
    datastart = read(f, END(UInt16))
    aspf = read(f, END(UInt16))
    pointrate = read(f, END)
    res1 = read(f, 137*2)

    tmp = read(f, END(UInt16))
    tmp_lr = read(f, END(UInt16))
    labelrange = (tmp == 0x3039) ? tmp_lr : nothing

    char4 = (read(f, END(UInt16)) == 0x3039)
    skip(f, 2)
    res2 = read(f, UInt16)

    eventtimes = Vector{eltype(END)}(undef, 18)
    read!(f, eventtimes, END)
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

    return Header{END}(paramptr, npoints, ampf, fframe, lframe, maxinterp, scale,
                     datastart, aspf, pointrate, res1, labelrange, res2, events, res3)
end

