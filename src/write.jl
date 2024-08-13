"round approximately (integer) numbers, or leave as is (to force an error when attempting to
convert)"
function roundapprox(::Type{T}, x; atol=0, rtol::Real=atol>0 ? 0 : √eps(x)) where T
    if ismissing(x)
        return missing
    else
        rounded = round(T,x)
        return isapprox(x, rounded; atol, rtol) ? rounded : convert(T, x)
    end
end

"""
    matrixround_ifintegers(x)

Return a matrix where each column has been rounded to integers if > 98% of the column are
already integers.

Analog samples are supposed to be stored as integers (regardless of storage format); but
this is not always the case. Due to floating-point inaccuracies, the processed (to be in
real/physical units) data may not transform exactly back to an integer. This function
assumes that these cases are rare (<2% of samples) when analog data is (correctly) stored as
integers, but that otherwise, the signal must be pre-scaled and therefore non-integer.
"""
function matrixround_ifintegers(x)
    y = similar(x)
    rows = size(x, 1)
    for (i,c) in enumerate(eachcol(x))
        if count(isinteger, c)/rows > .98 # integer analog samples stored as floats
            @views y[:,i] = round.(c)
        else
            @views y[:,i] = c
        end
    end
    return y
end

function makeresiduals(f::C3DFile{END}, m::String) where {END}
    scale = f.groups[:POINT][Float32, :SCALE]
    T = scale > 0 ? Int16 : eltype(END)
    scale = abs(scale)

    camera = f.cameras[m]
    residual = f.residual[m]
    nonmiss_residual = unsafe_nonmissing(f.residual[m])
    r = similar(camera, T)
    for i in eachindex(r)
        if ismissing(residual[i])
            r[i] = convert(T, nonmiss_residual[i])
        elseif iszero(residual[i])
            r[i] = convert(T, (camera[i] % Int16) << 8)
        else
            rvalue = (roundapprox(UInt8, residual[i]/scale)) |
                            ((camera[i] % Int16) << 8)
            r[i] = convert(T, rvalue)
        end
    end

    return r
end

function unsafe_nonmissing(x)
    real_eltype = nonmissingtype(eltype(x))
    return unsafe_wrap(Array{real_eltype,ndims(x)}, Ptr{real_eltype}(pointer(x)), size(x))
end

function assemble_analogdata(h::Header{END}, f::C3DFile{END}, ::Type{T}) where {END<:AbstractEndian,T}
    numchannels::Int = f.groups[:ANALOG][Int, :USED]
    aspf = h.aspf

    numchannels == 0 && return similar(Matrix{Float32}, (numpointframes(f),0,))

    analogdata  = similar(Matrix{Float32}, (numanalogframes(f),length(f.analog),))
    for (i, (analog, an_arr)) in enumerate(pairs(f.analog))
        analogdata[:,i] = an_arr
    end

    if numchannels == 1
        ANALOG_OFFSET = f.groups[:ANALOG][Float32, :OFFSET]
        ANALOG_SCALE = f.groups[:ANALOG][Float32, :GEN_SCALE] *
            f.groups[:ANALOG][Float32, :SCALE]

        analogdata .= analogdata ./ ANALOG_SCALE .+ ANALOG_OFFSET
        analogdata[:] = matrixround_ifintegers(analogdata)
    elseif numchannels > 1
        if haskey(f.groups[:ANALOG], :OFFSET2)
            off_labels = get_multipled_parameter_names(f.groups, :ANALOG, :OFFSET)
            VECANALOG_OFFSET = convert(Vector{Float32}, reduce(vcat,
                f.groups[:ANALOG][Vector{Int}, offset]
                for offset in off_labels))[1:numchannels]'
        else
            VECANALOG_OFFSET = convert(Vector{Float32},
                f.groups[:ANALOG][Vector{Int}, :OFFSET][1:numchannels])'
        end

        # addition of positive zero changes sign (to positive), negative zero addition
        # leaves sign as-is
        VECANALOG_OFFSET[iszero.(VECANALOG_OFFSET)] .= -0.0f0


        if haskey(f.groups[:ANALOG], :SCALE2)
            scale_labels = get_multipled_parameter_names(f.groups, :ANALOG, :SCALE)
            VECANALOG_SCALE = convert(Vector{Float32}, reduce(vcat,
                f.groups[:ANALOG][Vector{Int}, scale]
                for scale in scale_labels))[1:numchannels]'
        else
            VECANALOG_SCALE = f.groups[:ANALOG][Vector{Float32}, :SCALE][1:numchannels]'
        end
        VECANALOG_SCALE .*= f.groups[:ANALOG][Float32, :GEN_SCALE]

        # Dividing by zero causes NaNs; dividing by 1 does nothing
        VECANALOG_SCALE[iszero.(VECANALOG_SCALE)] .= 1.0f0

        analogdata .= analogdata ./ VECANALOG_SCALE .+ VECANALOG_OFFSET
        analogdata[:] = matrixround_ifintegers(analogdata)
    end

    return reshape(analogdata', numchannels*aspf, numpointframes(f))'
end

function assemble_pointdata(h::Header{END}, f::C3DFile{END}, ::Type{T}) where {END<:AbstractEndian,T}
    POINT_SCALE = abs(f.groups[:POINT][Float32, :SCALE])
    npoints = length(f.point)
    npoints == 0 && return similar(Matrix{Float32}, (numpointframes(f),0,))

    pointdata =  similar(Matrix{Float32}, (numpointframes(f),length(f.point)*4,))
    if T <: Int16
        for (i, (marker, pt_arr)) in enumerate(pairs(f.point))
            pointdata[:,(1:3).+(i-1)*4] .= unsafe_nonmissing(pt_arr)./POINT_SCALE
            pointdata[:,i*4] = makeresiduals(f, marker, T)
        end
    else
        for (i, (marker, pt_arr)) in enumerate(pairs(f.point))
            pointdata[:,(1:3).+(i-1)*4] = unsafe_nonmissing(pt_arr)
            pointdata[:,i*4] = makeresiduals(f, marker, T)
        end
    end

    return pointdata
end

function writedata(io::IO, f::C3DFile{END}, ::Type{T}) where {END<:AbstractEndian,T}
    h = Header(f)

    analogdata = assemble_analogdata(h, f, T)
    pointdata = assemble_pointdata(h, f, T)

    data = permutedims([pointdata analogdata])
    if T <: Int16
        data = END(Matrix{T})(roundapprox.(T, data))
    else
        data = END(Matrix{T})(Matrix{T}(data))
    end

    return write(io, data)
end

function edited_desc()
    return string(now(UTC), " UTC by C3D.jl v", pkgversion(@__MODULE__))
end

function writec3d(filename::String, f::C3DFile)
    open(filename, "w") do io
        writec3d(io, f)
    end
end

function add_edited!(f::C3DFile{END}) where END
    get!(f.groups, :MANUFACTURER, Group{END}("MANUFACTURER", "Manufacturer information"))
    p = get!(f.groups[:MANUFACTURER].params, :EDITED, Parameter("EDITED", "C3D file edit record", ""))
    if p isa Parameter{ScalarParameter{String}}
        p = Parameter{StringParameter}(p)
    end
    if isempty(p.payload.data)
        push!(p.payload.data, edited_desc())
    elseif isempty(first(p.payload.data))
        p.payload.data[1] = edited_desc()
    else
        push!(p.payload.data, edited_desc())
    end
    f.groups[:MANUFACTURER].params[:EDITED] = p

    return nothing
end

function writec3d(io, f::C3DFile{END}) where END
    add_edited!(f)

    # we may add groups and/or parameters during read validation; default gids for new
    # groups or parameters is zero
    for g in groups(f)
        g_gid = gid(g)
        if iszero(g_gid) # group we added during read validation
            # gids = collect(Iterators.filter(!iszero, (g.gid for g in groups(f))))
            # existing gids
            gids = filter(!iszero, gid.(groups(f)))

            # gids of group's parameters (to see if we can use an existing parameter's gid)
            # ignore default (zero) gids
            _gids = filter(x -> !iszero(x) && !(copysign(x, -1) in gids),
                unique(gid.(values(g))))

            @debug "Extant gids=$gids, parameter gids=$_gids"
            if isempty(_gids) # no viable gids from parameters
                # set gid to be first available gid (counting down from -1)
                g_gid = first(Iterators.filter(∉(gids)∘abs, Iterators.countfrom(-1, -1)))
            else
                # use first viable gid from parameters
                g_gid = copysign(first(_gids), -1)
            end

            @debug "Setting group $g gid to $g_gid"
            g.gid = g_gid
        end

        # update parameter gids to match group gid `g_gid`
        foreach(values(g)) do p
            p.gid = abs(g_gid)
        end
    end

    nb = 0
    header = Header(f)
    nb += write(io, header)
    f.groups[:POINT].params[:DATA_START].payload.data = header.datastart

    paramptr = ((header.paramptr % Int) - 1)*512
    @debug "padding $(max(paramptr-position(io),0)) bytes from $(string(position(io); base=16)) to parameter block at $(string(paramptr; base=16))" _id=gensym() maxlog=Int(paramptr-position(io)>0)
    # pad with zeros until `paramptr`
    nb += sum(x -> write(io, x),
        Iterators.repeated(0x00, max(paramptr - position(io), 0)); init=0)
    @assert position(io) == paramptr

    # Parameter section header
    # 0x5001 by convention, not required by spec, but some software is strict
    nb += write(io, 0x5001)

    # Size of parameter section in 512-byte blocks
    nb += write(io, Int8(header.datastart - 2))

    if END <: BigEndian
        nb += write(io, 0x56)
    elseif eltype(END) <: VaxFloatF # END <: LittleEndian
        nb += write(io, 0x55)
    else # eltype(END) == Float32
        nb += write(io, 0x54)
    end

    nb += sum(g -> write(io, g), groups(f))
    params = collect(parameters(f))
    nb += sum(p -> write(io, p, END), params[1:end-1])
    # Properly, the `pointer` in the last parameter should be zero to signify the end of the
    # parameter section
    nb += write(io, last(params), END; last=true)

    datastart = (header.datastart % Int - 1)*512
    # pad with zeros until the beginning of the data section
    @debug "padding $(max(datastart - position(io), 0)) bytes from 0x$(string(position(io); base=16)) to datastart at 0x$(string(datastart; base=16))" _id=gensym() maxlog=Int(datastart-position(io)>0)
    nb += sum(x -> write(io, x),
        Iterators.repeated(0x00, max(datastart - position(io), 0)); init=0)
    @assert position(io) == datastart

    T = f.groups[:POINT][Float32, :SCALE] > 0 ? Int16 : eltype(END)
    nb += writedata(io, f, T)

    fileend = cld(nb, 512)*512
    padend = 512 - rem(nb, 512)
    @debug "padding $padend bytes from 0x$(string(position(io); base=16)) to end of next 512-byte block" _id=gensym() maxlog=Int(padend>0)
    nb += sum(x -> write(io, x),
        Iterators.repeated(0x00, min(fileend - position(io), 512));
        init=0)

    return nb
end

