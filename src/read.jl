function calcresiduals(x::AbstractVector, scale)
    return (convert.(Int16, x) .% UInt8) .* abs(scale)
end

function readdata(
    io::IOStream, h::Header{END}, groups::Dict{Symbol,Group}
    ) where {END<:AbstractEndian}
    if iszero(groups[:POINT][Int, :DATA_START]-1)
        if !iszero(h.datastart-1)
            seek(io, (h.datastart-1)*512)
        else
            throw(ArgumentError("DATA_START missing/incorrect; cannot read file"))
        end
    else
        seek(io, (groups[:POINT][Int, :DATA_START]-1)*512)
    end

    format = groups[:POINT][Float32, :SCALE] > 0 ? Int16 : eltype(END)

    numframes::Int = numpointframes(groups)
    nummarkers::Int = groups[:POINT][Int, :USED]
    numchannels::Int = groups[:ANALOG][Int, :USED]
    pointrate = get(groups[:POINT], (Float32, :RATE), h.pointrate)
    if isinteger(get(groups[:ANALOG], (Float32, :RATE), pointrate)/pointrate)
        aspf::Int = convert(Int, get(groups[:ANALOG], (Float32, :RATE), pointrate)/pointrate)
    else
        aspf = h.aspf
    end

    est_data_size = numframes*sizeof(format)*(nummarkers*4 + numchannels*aspf)
    _iosize = stat(fd(io)).size
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

        pointtmp = Vector{format}(undef, nb)
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

        analogtmp = Matrix{format}(undef, (numchannels,aspf))
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

    if hasmarkers && format == Int16
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
"""
function readc3d(fn::AbstractString; paramsonly=false, validate=true,
                 missingpoints=true, strip_prefixes=false)
    io = open(fn, "r")

    groups, header, END = _readparams(fn, io)

    if validate
        validatec3d(header, groups)
    end

    if paramsonly
        point = Dict{String,Matrix{Union{Missing, Float32}}}()
        residual = Dict{String,Vector{Union{Missing, Float32}}}()
        cameras = Dict{String,Vector{UInt8}}()
        analog = Dict{String,Vector{Float32}}()
        close(io)
        return C3DFile(fn, header, groups, point, residual, cameras, analog)
    else
        (point, residual, analog) = readdata(io, header, groups)
        close(io)
    end

    res = C3DFile(fn, header, groups, point, residual, analog;
                  missingpoints, strip_prefixes)

    return res
end

function _readparams(fn::String, io::IO)
    params_ptr = read(io, UInt8)

    if read(io, UInt8) != 0x50
        error("File ", fn, " is not a valid C3D file")
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

    mark(io)
    header = read(io, Header{END})
    reset(io)

    groups = Dict{Symbol,Group}()
    if !iszero(paramblocks)
        gs = Array{Group,1}()
        ps = Array{Parameter,1}()
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
                    @debug "Pointer mismatch at position $(position(io)) where pointer was $np"
                    seek(io, np)
            elseif fail > 1 # this is the second failed attempt
                @debug "Second failed parameter read attempt from $(position(io))"
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
                    # Last readgroup failed, possibly due to a bad pointer. Reset to the ending
                    # location of the last successfully read parameter and try again. Count the failure.
                    reset(io)
                    @debug "Read group failed, last parameter ended at $(position(io)), pointer at $np" fail exception=(e,backtrace())
                    fail += 1
                finally
                    unmark(io) # Unmark the file regardless
                end
            elseif gid > 0 # Parameter
                # Reset to the beginning of the parameter
                skip(io, -2)
                try
                    push!(ps, readparam(io, END))
                    np = ps[end].pos + ps[end].np + length(ps[end]._name) + 2
                    moreparams = ps[end].np != 0 ? true : false
                    fail = 0
                catch e
                    reset(io)
                    @debug "Read group failed, last parameter ended at $(position(io)), pointer at $np" fail exception=(e,backtrace())
                    fail += 1
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

        groups = Dict{Symbol,Group}()
        gids = Dict{Int8,Symbol}()

        for group in gs
            groups[group.name] = group
            gids[abs(group.gid)] = group.name
        end

        for param in ps
            if haskey(gids, param.gid)
                groups[gids[param.gid]].params[param.name] = param
            else
                groupsym = Symbol("GID_$(param.gid)_MISSING")
                if !haskey(groups, groupsym)
                    groupname = string(groupsym)
                    groups[groupsym] = Group{END}(groupname, "Group was not defined in header"; gid=param.gid)
                end
                groups[groupsym].params[param.name] = param
            end
        end
    end

    return (groups, header, END)
end


