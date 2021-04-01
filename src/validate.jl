struct ValidateError <: Exception end

const rgroups = (:POINT, :ANALOG)

const descriptives = (:LABELS, :DESCRIPTIONS, :UNITS)

const rpoint = (:USED, :DATA_START, :FRAMES)
const ratescale = (:SCALE, :RATE)

const ranalog = (:USED, :GEN_SCALE, :OFFSET) ∪ ratescale
const bitsformat = (:BITS, :FORMAT)

const rforceplatf = (:TYPE, :ZERO, :CORNERS, :ORIGIN, :CHANNEL, :CAL_MATRIX)

const pointsigncheck = ((:POINT, :USED),
                   (:POINT, :DATA_START),
                   (:POINT, :FRAMES))

# const analogsigncheck = (:ANALOG, :USED)
# const fpsigncheck = (:FORCE_PLATFORM, :ZERO)

function validatec3d(header::Header, groups::Dict{Symbol,Group})
    # The following if-else ensures the minimum set of information needed to succesfully
    # read a C3DFile
    if !(rgroups ⊆ keys(groups))
        if !haskey(groups, :ANALOG)
            groups[:ANALOG] = Group(0, Int8(6), false, Int8(0), "ANALOG", :ANALOG, Int16(0),
                UInt8(22), "Analog data parameters", Dict{Symbol,Parameter}())
            groups[:ANALOG].params[:USED] = Parameter(0, Int8(5), false, Int8(0), "USED",
                :USED, Int16(0), UInt8(30), "Number of analog channels used",
                ScalarParameter(zero(Int16)))
        else
            d = setdiff(rgroups, keys(groups))
            msg = "Required group(s)"
            for p in d
                msg *= " :"*string(p)
            end
            msg *= " are missing"
            throw(ErrorException(msg))
        end
    end

    # Validate the :POINT group
    pointkeys = keys(groups[:POINT].params)
    if !(rpoint ⊆ pointkeys)
        # The minimum set of parameters in :POINT is rpoint
        d = setdiff(rpoint, pointkeys)
        msg = ":POINT is missing required parameter(s)"
        for p in d
            msg *= " :"*string(p)
        end
        throw(ErrorException(msg))
    end

    # Fix the sign for any point parameters that are likely to need it
    for (group, param) in pointsigncheck
        if any(signbit, groups[group].params[param].payload.data)
            groups[group].params[param] = unsigned(groups[group].params[param])
        end
    end

    POINT_USED = groups[:POINT][Int, :USED]
    ANALOG_USED = groups[:ANALOG][Int, :USED]
    if POINT_USED != 0 # There are markers
        # If there are markers, the additional set of required parameters is ratescale
        if !(ratescale ⊆ pointkeys)
            if !(:RATE ∈ pointkeys) && ANALOG_USED == 0
                # If there is no analog data, POINT:RATE isn't technically required
            else
                d = setdiff(rpoint, pointkeys)
                msg = ":POINT is missing required parameter(s)"
                for p in d
                    msg *= " :"*string(p)
                end
                throw(ErrorException(msg))
            end
        end

        if !(descriptives ⊆ pointkeys) # Check that the descriptive parameters exist
            if !haskey(groups[:POINT].params, :LABELS)
                # While the C3D file can technically be read in the absence of a LABELS
                # parameter, this implementation requires LABELS (for indexing)
                @debug ":POINT is missing parameter :LABELS"
                labels = [ "M"*string(i, pad=3) for i in 1:POINT_USED ]
                groups[:POINT].params[:LABELS] = Parameter(0, Int8(0), false,
                    abs(groups[:POINT].gid), "LABELS", :LABELS, Int16(0), UInt8(13),
                    "Marker labels", StringParameter(labels))
            elseif !haskey(groups[:POINT].params, :DESCRIPTIONS)
                @debug ":POINT is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:POINT].params, :UNITS)
                @debug ":POINT is missing parameter :UNITS"
            end
        elseif groups[:POINT].params[:LABELS] isa Parameter{ScalarParameter}
            # ie There is only one used marker (or the others are unlabeled)
            groups[:POINT].params[:LABELS] = Parameter{StringParameter}(groups[:POINT].params[:LABELS])
        end

        POINT_LABELS = groups[:POINT][Vector{String}, :LABELS]
        # Valid labels are required for each marker by the C3DFile constructor
        if any(isempty, POINT_LABELS) ||
           length(POINT_LABELS) < POINT_USED # Some markers don't have labels
            i = 2
            while length(POINT_LABELS) < POINT_USED
                # Check for the existence of a runoff labels group
                if haskey(groups[:POINT].params, Symbol("LABEL",i))
                    append!(POINT_LABELS, groups[:POINT][Vector{String}, Symbol("LABEL",i)])
                    i += 1
                else
                    push!(POINT_LABELS, "")
                end
            end

            idx = findall(isempty, POINT_LABELS)
            labels = [ "M"*string(i, pad=3) for i in 1:length(idx) ]
            POINT_LABELS[idx] .= labels
        end

        if !allunique(POINT_LABELS)
            dups = String[]
            for i in 1:POINT_USED
                if !in(POINT_LABELS[i], dups)
                    push!(dups, POINT_LABELS[i])
                else
                    m = match(r"_(?<num>\d+)$", POINT_LABELS[i])

                    if m === nothing
                        POINT_LABELS[i] *= "_2"
                        push!(dups, POINT_LABELS[i])
                    else
                        newlabel = POINT_LABELS[i][1:(m.offset - 1)] *
                            string('_',tryparse(Int,m[:num])+1)
                        POINT_LABELS[i] = newlabel
                        push!(dups, POINT_LABELS[i])
                    end
                end
            end
        end
    end # End validate :POINT

    # Validate the :ANALOG group
    analogkeys = keys(groups[:ANALOG].params)
    if !haskey(groups[:ANALOG].params, :USED)
        msg = ":ANALOG is missing required parameter :USED"
        throw(ErrorException(msg))
    end

    if signbit(ANALOG_USED)
        groups[:ANALOG].params[:USED] = unsigned(groups[:ANALOG].params[:USED])
    end

    if ANALOG_USED != 0 # There are analog channels

        @label analogkeychanged
        # If there are analog channels, the required set of parameters is ranalog
        if !(ranalog ⊆ analogkeys)
            if :OFFSETS ∈ analogkeys
                groups[:ANALOG].params[:OFFSET] = groups[:ANALOG].params[:OFFSETS]
                delete!(groups[:ANALOG].params, :OFFSETS)
                @goto analogkeychanged # OFFSETS might not be the only missing parameter
            else
                d = setdiff(ranalog, analogkeys)
                msg = ":ANALOG is missing required parameter(s)"
                for p in d
                    msg *= " :"*string(p)
                end
                throw(ErrorException(msg))
            end
        elseif !(descriptives ⊆ analogkeys) # Check that the descriptive parameters exist
            if !haskey(groups[:ANALOG].params, :LABELS)
                @debug ":ANALOG is missing parameter :LABELS"
                labels = [ "A"*string(i, pad=3) for i in 1:ANALOG_USED ]
                groups[:ANALOG].params[:LABELS] = Parameter{StringParameter}(0, Int8(0),
                    false, abs(groups[:ANALOG].gid), "LABELS", :LABELS, Int16(0), UInt8(14),
                    "Channel labels", StringParameter(labels))
            elseif !haskey(groups[:ANALOG].params, :DESCRIPTIONS)
                @debug ":ANALOG is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:ANALOG].params, :UNITS)
                @debug ":ANALOG is missing parameter :UNITS"
            end
        elseif groups[:ANALOG].params[:LABELS] isa ScalarParameter
            groups[:ANALOG].params[:LABELS] = StringParameter(groups[:ANALOG].params[:LABELS])
        end

        # Pad scale and offset if shorter than :USED
        l = length(groups[:ANALOG][Vector{Float32}, :SCALE])
        if l < ANALOG_USED
            append!(groups[:ANALOG][Vector{Float32}, :SCALE],
                    fill(one(Float32), ANALOG_USED - l))
        end

        l = length(groups[:ANALOG][Vector{Int16}, :OFFSET])
        if l < ANALOG_USED
            append!(groups[:ANALOG][Vector{Int16}, :OFFSET],
                    fill(one(Float32), ANALOG_USED - l))
        end

        ANALOG_LABELS = groups[:ANALOG][Vector{String}, :LABELS]
        if any(isempty, ANALOG_LABELS) ||
           length(ANALOG_LABELS) < ANALOG_USED # Some markers don't have labels
            i = 2
            while length(ANALOG_LABELS) < ANALOG_USED
                if haskey(groups[:ANALOG].params, Symbol("LABEL",i)) # Check for the existence of a runoff labels group
                    append!(ANALOG_LABELS, groups[:ANALOG][Vector{String}, Symbol("LABEL",i)])
                    i += 1
                else
                    push!(ANALOG_LABELS, "")
                end
            end

            idx = findall(isempty, ANALOG_LABELS)
            labels = [ "A"*string(i, pad=3) for i in 1:length(idx) ]
            ANALOG_LABELS[idx] .= labels
        end

        if !allunique(ANALOG_LABELS)
            dups = String[]
            for i in 1:ANALOG_USED
                if !in(ANALOG_LABELS[i], dups)
                    push!(dups, ANALOG_LABELS[i])
                else
                    m = match(r"_(?<num>\d+)$", ANALOG_LABELS[i])

                    if m === nothing
                        ANALOG_LABELS[i] *= "_2"
                        push!(dups, ANALOG_LABELS[i])
                    else
                        newlabel = ANALOG_LABELS[i][1:(m.offset - 1)] *
                            string('_', tryparse(Int, m[:num]) + 1)
                        ANALOG_LABELS[i] = newlabel
                        push!(dups, ANALOG_LABELS[i])
                    end
                end
            end
        end
    end # End if analog channels exist

    return nothing
end

