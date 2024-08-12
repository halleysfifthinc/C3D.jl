function calcresiduals(x::AbstractVector, scale)
    return (convert.(Int16, x) .% UInt8) .* abs(scale)
end

function calcresiduals!(x::AbstractVector{T}, indices::Vector{I}, scale) where {T,I}
    @inbounds for i in eachindex(x)
        if indices[i]
            x[i] = (convert(Int16, x[i]) % UInt8) * abs(scale)
        end
    end

    return nothing
end

function readdata(
    io::IO, h::Header{END}, groups::LittleDict{Symbol,Group{END},Vector{Symbol},Vector{Group{END}}}, ::Type{F}
    ) where {END<:AbstractEndian, F}
    numframes::Int = numpointframes(groups)
    nummarkers::Int = groups[:POINT][Int, :USED]
    numchannels::Int = groups[:ANALOG][Int, :USED]
    pointrate = get(groups[:POINT], (Float32, :RATE), h.pointrate::Float32)::Float32
    analograte = get(groups[:ANALOG], (Float32, :RATE), pointrate)::Float32
    if isinteger(analograte/pointrate)::Bool
        aspf::Int = convert(Int, analograte/pointrate)
    else
        aspf = h.aspf
    end

    est_data_size = numframes*sizeof(F)*(nummarkers*4 + numchannels*aspf)
    if io isa IOBuffer
        _iosize = io.size
    else
        _iosize = stat(io).size
    end
    rem_file_size = _iosize - position(io)
    if est_data_size > rem_file_size
        @debug "Estimated DATA size: $(Base.format_bytes(est_data_size)); \
            remaining file data: $(Base.format_bytes(rem_file_size))"
        # Some combination of numframes, nummarkers, numchannels, aspf, or format is wrong
        # (or the end of the file has been cut off)
        # Check any duplicated info and use instead
        #
        if nummarkers > h.npoints
            # Needed to correctly read artifact"sample27/kyowadengyo.c3d"
            nummarkers = h.npoints
            groups[:POINT].params[:USED].payload.data = nummarkers
        end

        # Remaining checks will be withheld until triggering test cases are demonstrated
        # if numchannels > h.ampf/aspf
        #     numchannels = h.ampf/aspf
        # end
        # est_data_size = numframes*sizeof(format)*(nummarkers*4 + numchannels*aspf)
        # rem_file_size = stat(fd(io)).size - position(io)
        # @debug "Estimated DATA size: $(Base.format_bytes(est_data_size)); \
        #     remaining file data: $(Base.format_bytes(rem_file_size))"
    end

    # Read data in a transposed structure for better read/write speeds due to Julia being
    # column-order arrays
    hasmarkers = !iszero(nummarkers)
    if hasmarkers
        point = zeros(Float32, nummarkers*3, numframes)
        residuals = zeros(Int32, nummarkers, numframes)

        nb = nummarkers*4
        pointidxs = filter(x -> x % 4 != 0, 1:nb)
        residxs = filter(x -> x % 4 == 0, 1:nb)

        pointtmp = Vector{F}(undef, nb)
        pointview = view(pointtmp, pointidxs)
        resview = view(pointtmp, residxs)
    else
        point = Array{Float32,2}(undef, 0,0)
        residuals = Array{Int32,2}(undef, 0,0)
    end

    haschannels = !iszero(numchannels)
    if haschannels
        # Analog Samples Per Frame => ASPF
        analog = zeros(Float32, numchannels, aspf*numframes)

        analogtmp = Matrix{F}(undef, (numchannels,aspf))
    else
        analog = Array{Float32,2}(undef, 0,0)
    end

    @inbounds for i in 1:numframes
        if hasmarkers
            if _iosize - position(io) ≥ sizeof(pointtmp)
                read!(io, pointtmp, END)
                point[:,i] .= convert.(Float32, pointview)
                residuals[:,i] .= convert.(Int32, resview)
            else
                @debug "End-of-file reached before expected; frame$(length(i:numframes) > 1 ? "s" : "") $(i:numframes) \
                    are missing"
                break
            end
        end
        if haschannels
            if _iosize - position(io) ≥ sizeof(analogtmp)
                read!(io, analogtmp, END)
                analog[:,((i-1)*aspf+1):(i*aspf)] .= convert.(Float32, analogtmp)
            else
                @debug "End-of-file reached before expected; frame$(length(i:numframes) > 1 ? "s" : "") $(i:numframes) \
                    are missing"
                break
            end
        end
    end

    if hasmarkers && F == Int16
        # Multiply or divide by [:point][:scale]
        POINT_SCALE = groups[:POINT][Float32, :SCALE]
        point .*= abs(POINT_SCALE)
    end

    if haschannels
        if numchannels == 1
            ANALOG_OFFSET = groups[:ANALOG][Float32, :OFFSET]
            SCALE = groups[:ANALOG][Float32, :GEN_SCALE] * groups[:ANALOG][Float32, :SCALE]
            analog .= (analog .- ANALOG_OFFSET) .* SCALE
        else
            VECANALOG_OFFSET = groups[:ANALOG][Vector{Int}, :OFFSET][1:numchannels]
            VECSCALE = groups[:ANALOG][Float32, :GEN_SCALE] .*
                            groups[:ANALOG][Vector{Float32}, :SCALE][1:numchannels]

            analog .= (analog .- VECANALOG_OFFSET) .* VECSCALE
        end
    end

    return (permutedims(point), permutedims(residuals), permutedims(analog))
end

"""
    readc3d(fn)

Read the C3D file at `fn`.

# Keyword arguments
- `paramsonly::Bool = false`: Only reads the header and parameters
- `validateparams::Bool = true`: Validates parameters against C3D requirements
- `missingpoints::Bool = true`: Sets invalid points to `missing`
- `handle_duplicate_parameters::Symbol = :keeplast`: How to handle multiple parameters in a
  group with the same name. Options are:
  - `:drop`: The first parameter with the duplicated name is used and the rest are dropped.
  - `:keeplast`: The last parameter with the duplicated name is kept.
  - `:append_position`: All duplicate parameters are kept and their position in the C3D file
    is appended to their name.

"""
function readc3d(fn::AbstractString; paramsonly=false, validate=true,
    handle_duplicate_parameters=:keeplast, missingpoints=true, strip_prefixes=false)

    handle_duplicate_parameters ∈ (:drop, :keeplast, :append_count) || throw(ArgumentError(
        "Invalid `handle_duplicate_parameters`. Got :$handle_duplicate_parameters. Check \
the docstring for valid options."))

    io = open(fn, "r")

    params_ptr = read(io, UInt8)

    if read(io, UInt8) != 0x50
        throw(error("File ", stat(fd(io)).desc, " is not a valid C3D file"))
    end

    # Jump to parameters block
    seek(io, (params_ptr - 1) * 512)

    # Skip 2 reserved bytes
    # TODO: store bytes for saving modified files
    skip(io, 2)

    paramblocks = read(io, UInt8)
    proctype = read(io, Int8)

    FType = Float32

    # Deal with host big-endianness in the future
    if proctype == 0x54
        # little-endian
        END = LE{FType}
    elseif proctype == 0x55
        # DEC floats; little-endian
        FType = VaxFloatF
        END = LE{FType}
    elseif proctype == 0x56
        # big-endian
        END = BE{FType}
    else
        error("Malformed processor type. Expected 0x54, 0x55, or 0x56. Found ", proctype)
    end

    groups, header = _readparams(io, paramblocks, END, handle_duplicate_parameters)

    if validate
        validatec3d(header, groups)
    end

    if paramsonly
        point = OrderedDict{String,Matrix{Union{Missing, Float32}}}()
        residual = OrderedDict{String,Vector{Union{Missing, Float32}}}()
        cameras = OrderedDict{String,Vector{UInt8}}()
        analog = OrderedDict{String,Vector{Float32}}()
        close(io)
        return C3DFile(fn, header, groups, point, residual, cameras, analog)
    else
        format = groups[:POINT][Float32, :SCALE] > 0 ? Int16 : eltype(END)::Type

        if iszero(groups[:POINT][Int, :DATA_START]-1)
            if !iszero(header.datastart-1)
                seek(io, (header.datastart-1)*512)
            else
                throw(ArgumentError("DATA_START missing/incorrect; cannot read file"))
            end
        else
            seek(io, (groups[:POINT][Int, :DATA_START]-1)*512)
        end

        (point, residual, analog) = readdata(io, header, groups, format)
        close(io)
    end

    res = C3DFile(fn, header, groups, point, residual, analog;
                  missingpoints, strip_prefixes)

    return res
end

"requires a::Vector{Parameter} sorted by gid; returns views"
function split_filter!(f, a)
    if isempty(a)
        return similar(a, ntuple(_-> 0, ndims(a))), @view a[end+1:end]
    end

    true_is = searchsorted(a, first(a); by=f)
    trues = a[true_is]
    if isempty(true_is)
        @views falses = a[begin:end]
    else
        @views falses = a[last(true_is)+1:end]
    end

    return trues, falses
end

function isduplicate(x, a; by=identity)
    return count(==(by(x))∘by, a) > 1
end

function _readparams(io::IO, paramblocks, ::Type{END}, handle_duplicate_parameters::Symbol) where {END}
    mark(io)
    header = read(io, Header{END})
    reset(io)

    if !iszero(paramblocks)
        gs = Vector{Group{END}}()
        ps = Vector{Parameter}()
        moreparams = true
        fail = 0
        np = 0

        skip(io, 1)
        if read(io, Int8) < 0
            # Group
            skip(io, -2)
            push!(gs, read(io, Group{END}))
            np = gs[end].pos + gs[end].np + length(gs[end]._name) + 2
            moreparams = gs[end].np != 0 ? true : false
        else
            # Parameter
            skip(io, -2)
            push!(ps, readparam(io, END))
            np = ps[end].pos + ps[end].np + length(ps[end]._name) + 2
            moreparams = ps[end].np != 0 ? true : false
        end

        while moreparams
            # Mark current position in file in case the pointer is incorrect
            mark(io)
            if fail === 0 && np != position(io)
                @debug "Pointer mismatch at position $(string(position(io); base=16)) where pointer was $(string(np; base=16))"
                seek(io, np)
            elseif fail > 1 # this is the second failed attempt
                @debug "Second failed parameter read attempt from $(string(position(io); base=16))"
                break
            end

            # Read the next two bytes to get the gid
            skip(io, 1)
            local gid = read(io, Int8)
            if gid < 0 # Group
                # Reset to the beginning of the group
                skip(io, -2)
                try
                    push!(gs, read(io, Group{END}))
                    np = gs[end].pos + gs[end].np + length(gs[end]._name) + 2
                    moreparams = gs[end].np != 0 ? true : false # break if the pointer is 0 (ie the parameters are finished)
                    fail = 0 # reset fail counter following a successful read
                catch e
                    if e isa AssertionError
                        # Last readgroup failed, possibly due to a bad pointer. Reset to the ending
                        # location of the last successfully read parameter and try again. Count the failure.
                        reset(io)
                        @debug "Read group failed, last parameter ended at $(string(position(io); base=16)), pointer at $(string(np; base=16))" fail exception=(e,catch_backtrace())
                        fail += 1
                    else
                        rethrow(e)
                    end
                finally
                    unmark(io) # Unmark the file regardless
                end
            elseif gid > 0 # Parameter
                # Reset to the beginning of the parameter
                skip(io, -2)
                try
                    lastps = readparam(io, END)
                    push!(ps, lastps)
                    moreparams = lastps.np != 0 ? true : false
                    np = _position(lastps) + Int(lastps.np) + length(lastps._name) + 2
                    fail = 0
                catch e
                    if e isa AssertionError || e isa ParameterTypeError
                        reset(io)
                        @debug "Read group failed, last parameter ended at $(string(position(io); base=16)), pointer at $(string(np; base=16))" fail exception=(e,catch_backtrace())
                        fail += 1
                    else
                        rethrow(e)
                    end
                finally
                    unmark(io)
                end
            else # Last parameter pointer is incorrect (assumption)
                # The group ID should never be zero, if it is, the most likely explanation is
                # that the pointer is incorrect (eg the pointer was not fixed when the previously
                # last parameter was deleted or moved)
                @debug "Bad last position. Assuming parameter section is finished."
                break
            end
        end

        group_names = map(g -> g.name, gs)
        dup_group_names = findduplicates(group_names)
        if !isempty(dup_group_names)
            # @debug "duplicate group names detected"
            if !allunique(gid.(gs)) # Duplicate names with the same GID
                for group in gs
                    group.name ∈ dup_group_names || continue

                    @warn "Multiple groups with the same name \"$(group.name)\" and \
group ID `$(gid(group))`. The second duplicate group will be deleted to keep group names
unique (no parameters will be lost)." _id=(group.name, gid(group)) maxlog=1

                    # could be more than 1 duplicate
                    is = findall(==(group.name)∘(g->g.name), gs)
                    @assert !isempty(is)
                    @assert group === gs[first(is)]

                    # i.e. we're deleting *after* `group` and therefore deleting will
                    # only affect future iterations (by not running on the
                    # already-handled duplicate)

                    deleteat!(gs, is)
                end
            else # Duplicate names with different GIDs
                for group in gs
                    group.name ∈ dup_group_names || continue

                    # @debug group isduplicate(group, gs; by=(g->g.name))
                    @warn "Multiple groups with the same name \"$(group.name)\". The \
group ID will be appended to the duplicate group names to keep group names unique." _id=group.name maxlog=1
                    dups = findall(==(group.name)∘(g->g.name), gs)
                    for i in dups
                        gs[i].name = Symbol(gs[i].name, "_", gid(gs[i]))
                    end
                end
            end
        end

        group_names = map(g -> g.name, gs)
        groups = LittleDict{Symbol,Group{END},Vector{Symbol},Vector{Group{END}}}(group_names, gs)
        sort!(ps; by=gid)
        psv = @view ps[begin:end]

        for group in sort(gs; by=gid)
            group_params, psv = split_filter!(gid, psv)
            if isempty(group_params)
               @debug "group $(group.name) is empty" group_params, psv
               break
            end
            unique!(identity, group_params; seen=Set{Parameter}()) # remove literal duplicates

            # check for params with duplicate names
            param_names = map(name, group_params)
            dup_names = findduplicates(param_names)
            if !isempty(dup_names)
                # @debug "duplicate parameters detected in" group
                if handle_duplicate_parameters === :drop
                    # @debug "dropping duplicates"
                    unique!(name, group_params)
                elseif handle_duplicate_parameters === :keeplast
                    # @debug "keeping last duplicate" issorted(_position.(group_params))
                    dups = similar(BitVector, axes(group_params, 1))
                    dups .= false
                    _dups = similar(dups)
                    for _name in dup_names
                        for i in eachindex(_dups)
                            _dups[i] = name(group_params[i]) === name
                        end
                        # if count(_dups) > 1
                        #     @debug "found `duplicates` and keeping `last(duplicates)`" group_params[_dups], group_params[findlast(_dups)]
                        # end
                        count(_dups) > 1 || continue
                        i = findlast(_dups)
                        _dups[i] = false
                        dups .|= _dups
                    end
                    deleteat!(group_params, dups)
                elseif handle_duplicate_parameters === :append_count
                    # @debug "appending duplicate count to duplicate names; $(length(dup_names)) parameters with duplicated names"
                    dups = similar(BitVector, axes(group_params, 1))
                    dups .= false
                    _dups = similar(dups)
                    for _name in dup_names
                        for i in eachindex(_dups)
                            _dups[i] = name(group_params[i]) === name
                        end
                        count(_dups) > 1 || continue
                        # @debug "$(count(_dups)) duplicate parameters with name $(_name)"
                        dups .|= _dups
                    end
                    cnts = Dict{Symbol,Int}(zip(dup_names, zeros(Int, axes(dup_names,1))))
                    for i in eachindex(dups)
                        dups[i] || continue
                        param = group_params[i]
                        cnt = cnts[param.name] += 1
                        # @debug "$(param.name) => $(Symbol(param.name, "_", cnt))"
                        param.name = Symbol(param.name, "_", cnt)
                    end
                end
                param_names = map(name, group_params)
            end

            sizehint!(group.params, length(group_params))
            OrderedCollections.add_new!.(Ref(group.params), param_names, group_params)
        end

        while !isempty(psv)
            _gid = gid(psv[1])
            group_params, psv = split_filter!(p -> gid(p) === _gid, psv)
            groupsym = Symbol("GID_$(_gid)_MISSING")

            param_names = map(g -> g.name, group_params)
            @assert allunique(param_names)::Bool

            if !haskey(groups, groupsym)
                groupname = string(groupsym)
                group = Group{END}(groupname, "Group was not defined in header",
                    LittleDict(param_names, group_params); gid=_gid)
                groups[groupsym] = group
            else
                group = groups[groupsym]

                sizehint!(group.params, length(group_params))
                OrderedCollections.add_new!.(Ref(group.params), param_names, group_params)
            end
        end
    else
        groups = LittleDict{Symbol,Group{END}}(Symbol[], Group{END}[])
    end

    return (groups, header, END)
end


