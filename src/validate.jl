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

function validate(header::Header, groups::Dict{Symbol,Group}; complete=false)
    # The following if-else ensures the minimum set of information needed to succesfully read a C3DFile
    if !(rgroups ⊆ keys(groups))
        if !haskey(groups, :ANALOG)
            groups[:ANALOG] = Group(0, Int8(6), false, Int8(0), "ANALOG", :ANALOG, Int16(0), UInt8(22), "Analog data parameters", Dict{Symbol,AbstractParameter}())
            groups[:ANALOG].params[:USED] = ScalarParameter(0, Int8(5), false, Int8(0), "USED", :USED, Int16(0), zero(Int16), UInt8(30), "Number of analog channels used")
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
        if any(signbit.(groups[group].params[param].data))
            groups[group].params[param] = unsigned(groups[group].params[param])
        end
    end

    if groups[:POINT].USED != 0 # There are markers
        if !(ratescale ⊆ pointkeys) # If there are markers, the additional set of required parameters is ratescale
            if !(:RATE ∈ pointkeys) && groups[:ANALOG].USED == 0
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
                # While the C3D file can technically be read in the absence of a LABELS parameter,
                # this implementation requires LABELS (for indexing)
                @debug ":POINT is missing parameter :LABELS"
                labels = [ "M"*string(i, pad=3) for i in 1:groups[:POINT].USED ]
                groups[:POINT].params[:LABELS] =
                      StringParameter(0, Int8(0), false, abs(groups[:POINT].gid), "LABELS", :LABELS, Int16(0), labels, UInt8(13), "Marker labels")
            elseif !haskey(groups[:POINT].params, :DESCRIPTIONS)
                @debug ":POINT is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:POINT].params, :UNITS)
                @debug ":POINT is missing parameter :UNITS"
            end
        elseif groups[:POINT].params[:LABELS] isa ScalarParameter # ie There is only one used marker (or the others are unlabeled)
            groups[:POINT].params[:LABELS] = StringParameter(groups[:POINT].params[:LABELS])
        end

        # Valid labels are required for each marker by the C3DFile constructor
        if any(isempty.(groups[:POINT].LABELS)) ||
           length(groups[:POINT].LABELS) < groups[:POINT].USED # Some markers don't have labels
            i = 2
            while length(groups[:POINT].LABELS) < groups[:POINT].USED
                if haskey(groups[:POINT].params, Symbol("LABEL",i)) # Check for the existence of a runoff labels group
                    append!(groups[:POINT].LABELS, groups[:POINT].params[Symbol("LABEL",i)].data)
                    i += 1
                else
                    push!(groups[:POINT].LABELS, "")
                end
            end

            idx = findall(isempty, groups[:POINT].LABELS)
            labels = [ "M"*string(i, pad=3) for i in 1:length(idx) ]
            groups[:POINT].LABELS[idx] .= labels
        end

        if length(unique(groups[:POINT].LABELS)) !== length(groups[:POINT].LABELS)
            dups = String[]
            for i in 1:groups[:POINT].USED
                if !in(groups[:POINT].LABELS[i], dups)
                    push!(dups, groups[:POINT].LABELS[i])
                else
                    m = match(r"_(?<num>\d+)$", groups[:POINT].LABELS[i])

                    if m == nothing
                        groups[:POINT].LABELS[i] *= "_2"
                        push!(dups, groups[:POINT].LABELS[i])
                    else
                        newlabel = groups[:POINT].LABELS[i][1:(m.offset - 1)]*string('_',tryparse(Int,m[:num])+1)
                        groups[:POINT].LABELS[i] = newlabel
                        push!(dups, groups[:POINT].LABELS[i])
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

    if signbit(groups[:ANALOG].USED)
        groups[:ANALOG].params[:USED] = unsigned(groups[:ANALOG].params[:USED])
    end

    if groups[:ANALOG].USED != 0 # There are analog channels

        @label analogkeychanged
        if !(ranalog ⊆ analogkeys) # If there are analog channels, the required set of parameters is ranalog
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
                labels = [ "A"*string(i, pad=3) for i in 1:groups[:ANALOG].USED ]
                groups[:ANALOG].params[:LABELS] =
                      StringParameter(0, Int8(0), false, abs(groups[:ANALOG].gid), "LABELS", :LABELS, Int16(0), labels, UInt8(14), "Channel labels")
            elseif !haskey(groups[:ANALOG].params, :DESCRIPTIONS)
                @debug ":ANALOG is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:ANALOG].params, :UNITS)
                @debug ":ANALOG is missing parameter :UNITS"
            end
        elseif groups[:ANALOG].params[:LABELS] isa ScalarParameter
            groups[:ANALOG].params[:LABELS] = StringParameter(groups[:ANALOG].params[:LABELS])
        end

        # Pad scale and offset if shorter than :USED
        l = length(groups[:ANALOG].SCALE)
        if l < groups[:ANALOG].USED
            append!(groups[:ANALOG].params[:SCALE].data, fill(Float32(1.0), groups[:ANALOG].USED - l))
        end

        l = length(groups[:ANALOG].OFFSET)
        if l < groups[:ANALOG].USED
            append!(groups[:ANALOG].params[:OFFSET].data, fill(Float32(1.0), groups[:ANALOG].USED - l))
        end

        if any(isempty.(groups[:ANALOG].LABELS)) ||
           length(groups[:ANALOG].LABELS) < groups[:ANALOG].USED # Some markers don't have labels
            i = 2
            while length(groups[:ANALOG].LABELS) < groups[:ANALOG].USED
                if haskey(groups[:ANALOG].params, Symbol("LABEL",i)) # Check for the existence of a runoff labels group
                    append!(groups[:ANALOG].LABELS, groups[:ANALOG].params[Symbol("LABEL",i)].data)
                    i += 1
                else
                    push!(groups[:ANALOG].LABELS, "")
                end
            end

            idx = findall(isempty, groups[:ANALOG].LABELS)
            labels = [ "A"*string(i, pad=3) for i in 1:length(idx) ]
            groups[:ANALOG].LABELS[idx] .= labels
        end

        if length(unique(groups[:ANALOG].LABELS)) !== length(groups[:ANALOG].LABELS)
            dups = String[]
            for i in 1:groups[:ANALOG].USED
                if !in(groups[:ANALOG].LABELS[i], dups)
                    push!(dups, groups[:ANALOG].LABELS[i])
                else
                    m = match(r"_(?<num>\d+)$", groups[:ANALOG].LABELS[i])

                    if m == nothing
                        groups[:ANALOG].LABELS[i] *= "_2"
                        push!(dups, groups[:ANALOG].LABELS[i])
                    else
                        newlabel = groups[:ANALOG].LABELS[i][1:(m.offset - 1)]*string('_',tryparse(Int,m[:num])+1)
                        groups[:ANALOG].LABELS[i] = newlabel
                        push!(dups, groups[:ANALOG].LABELS[i])
                    end
                end
            end
        end
    end # End if analog channels exist

    nothing
end

