# Round approximately (integer) numbers, or leave as is (to error when attempting to
# convert)
roundapprox(T, x::Missing; atol=0, rtol=0) = missing
function roundapprox(T, x; atol=0, rtol::Real=atol>0 ? 0 : √eps(x))
    if ismissing(x)
        return missing
    else
        return isapprox(x, round(T,x); atol, rtol) ? round(T,x) : convert(T, x)
    end
end

function makeresiduals(f::C3DFile{END}, m::String) where {END}
    scale = f.groups[:POINT][Float32, :SCALE]
    T = scale > 0 ? Int16 : eltype(END)
    scale = abs(scale)

    r = similar(f.cameras[m], T)
    for i in eachindex(r)
        if ismissing(f.residual[m][i])
            r[i] = convert(T, Int16(-1))
        elseif iszero(f.residual[m][i])
            r[i] = zero(T)
        else
            rvalue = (roundapprox(Int16, f.residual[m][i]/scale)) |
                            ((f.cameras[m][i] % UInt16) << 8)
            r[i] = convert(T, rvalue)
        end
    end

    return r
end

function writedata(io::IO, f::C3DFile{END}) where {END<:AbstractEndian}
    h = Header(f)
    POINT_SCALE = f.groups[:POINT][Float32, :SCALE]
    T = POINT_SCALE > 0 ? Int16 : eltype(END)
    POINT_SCALE = abs(POINT_SCALE)
    numchannels::Int = f.groups[:ANALOG][Int, :USED]
    aspf = h.aspf

    analogdata = reduce(hcat, (f.analog[channel] for channel in keys(f.analog) ))
    if numchannels == 1
        ANALOG_OFFSET = f.groups[:ANALOG][Float32, :OFFSET]
        SCALE = f.groups[:ANALOG][Float32, :GEN_SCALE] * f.groups[:ANALOG][Float32, :SCALE]
        analogdata .= analogdata ./ SCALE .+ ANALOG_OFFSET
    elseif numchannels > 1
        VECANALOG_OFFSET = f.groups[:ANALOG][Vector{Int}, :OFFSET][1:numchannels]
        VECSCALE = f.groups[:ANALOG][Float32, :GEN_SCALE] .*
                        f.groups[:ANALOG][Vector{Float32}, :SCALE][1:numchannels]

        analogdata .= (analogdata' ./ VECSCALE .+ VECANALOG_OFFSET)'
    end
    analog = permutedims(reshape(permutedims(analogdata), numchannels*aspf, :))
    if T <: Int16
        pointdata = reduce(hcat, ([roundapprox.(T, f.point[marker]./POINT_SCALE) makeresiduals(f, marker)]
            for marker in keys(f.point) ))
    else
        pointdata = reduce(hcat, ([f.point[marker] makeresiduals(f, marker)]
            for marker in keys(f.point) ))
    end
    missings = findall(ismissing, pointdata)
    if !isempty(missings)
        pointdata[missings] .= zero(Float32)
    end

    data = permutedims([pointdata analog])
    data = END(Matrix{eltype(T)})(Matrix{eltype(T)}(data))

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

    nb = 0
    header = Header(f)
    nb += write(io, header)
    f.groups[:POINT].params[:DATA_START].payload.data = header.datastart

    # pad with zeros until `paramptr`
    nb += sum(x -> write(io, x),
        Iterators.repeated(0x00, max((f.header.paramptr-1)*512 - position(io), 0)); init=0)

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

    # nb += sum(g -> write(io, g), sort(groups(f); by=(g->abs(g.gid))))
    nb += sum(g -> write(io, g), groups(f))
    params = collect(parameters(f))
    nb += sum(p -> write(io, p, END), params[1:end-1])
    # Properly, the `pointer` in the last parameter should be zero to signify the end of the
    # parameter section
    nb += write(io, last(params), END; last=true)

    # pad with zeros until the beginning of the data section
    # @debug "padding from  $(position(io)) to $(max((header.datastart - 1)*512 - position(io), 0))"
    nb += sum(x -> write(io, x),
        Iterators.repeated(0x00, max((header.datastart - 1)*512 - position(io), 0)); init=0)

    nb += writedata(io, f)

    # @debug "padding from  $(position(io)) to end of next block (512 bytes) multiple ($(min(round(Int, nb/512, RoundUp)*512 - position(io), 512)))"
    nb += sum(x -> write(io, x),
        Iterators.repeated(0x00, min(round(Int, nb/512, RoundUp)*512 - position(io), 512));
        init=0)

    return nb
end

