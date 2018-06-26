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
        d = setdiff(rgroups, keys(groups))
        msg = "Required group(s)"
        for p in d
            msg *= " :"*string(p)
        end
        msg *= " are missing"
        throw(ErrorException(msg))
    else
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

        # Fix the sign for any parameters that are likely to need it
        for (group, param) in pointsigncheck
            if any(signbit.(groups[group].params[param].data))
                groups[group].params[param] = unsigned(groups[group].params[param])
            end
        end

        if groups[:POINT].USED != 0 # There are markers
            if !(ratescale ⊆ pointkeys) # If there are markers, the additional set of required parameters is ratescale
                d = setdiff(rpoint, pointkeys)
                msg = ":POINT is missing required parameter(s)"
                for p in d
                    msg *= " :"*string(p)
                end
                throw(ErrorException(msg))
            elseif !(descriptives ⊆ pointkeys) # Check that the descriptive parameters exist
                if !haskey(groups[:POINT].LABELS)
                    # While the C3D file can technically be read in the absence of a LABELS parameter,
                    # this implementation requires LABELS (for indexing)
                    @debug ":POINT is missing parameter :LABELS"
                    labels = [ "M"*string(i, pad=3) for i in 1:groups[:POINT].USED ]
                    push!(groups[:POINT],
                          StringParameter(NaN, NaN, false, abs(groups[:POINT].gid), "LABELS", :LABELS, NaN, labels, 13, "Marker labels"))
                elseif !haskey(groups[:POINT].DESCRIPTIONS)
                    @debug ":POINT is missing parameter :DESCRIPTIONS"
                elseif !haskey(groups[:POINT].UNITS)
                    @debug ":POINT is missing parameter :UNITS"
                end
            end

            # Valid labels are required for each marker by the C3DFile constructor
            if length(groups[:POINT].LABELS) < groups[:POINT].USED # Some markers don't have labels
                i = 2
                while length(groups[:POINT].LABELS) < groups[:POINT].USED
                    if haskey(groups[:POINT].params, Symbol("LABEL",i)) # Check for the existence of a runoff labels group
                        append!(groups[:POINT].LABELS, groups[:POINT].params[Symbol("LABEL",i)])
                    else
                        labels = [ "M"*string(i, pad=3) for i in length(groups[:POINT].LABELS):groups[:POINT].USED ]
                        append!(groups[:POINT].LABELS, labels)
                    end
                    i += 1
                end
            end

            # Unique labels are required for each marker
            if length(unique(groups[:POINT].LABELS)) != length(groups[:POINT].LABELS)
                dups = String[]
                for i in 1:groups[:POINT].USED
                    if !in(groups[:POINT].LABELS[i], dups)
                        push!(dups, groups[:POINT].LABELS[i])
                    else # we have a duplicate
                        m = match(r"\d+$", groups[:POINT].LABELS[i])

                        # Add a number at the end unless there already is one, in which case increment it
                        if m == nothing
                            groups[:POINT].LABELS[i] *= "2"
                            push!(dups, groups[:POINT].LABELS[i])
                        else
                            newlabel = groups[:POINT].LABELS[i][1:(m.offset - 1)]*string(parse(m.match)+1)
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

        if signbit.(groups[:ANALOG].USED)
            groups[:ANALOG].params[:USED] = unsigned(groups[:ANALOG].params[:USED])
        end

        if groups[:ANALOG].USED != 0 # There are analog channels

            if !(ranalog ⊆ analogkeys) # If there are analog channels, the required set of parameters is ranalog
                d = setdiff(rpoint, keys(groups[:ANALOG].params))
                msg = ":ANALOG is missing required parameter(s)"
                for p in d
                    msg *= " :"*string(p)
                end
                throw(ErrorException(msg))
            elseif !(descriptives ⊆ analogkeys) # Check that the descriptive parameters exist
                if !haskey(groups[:ANALOG].LABELS)
                    @debug ":ANALOG is missing parameter :LABELS"
                    labels = [ "A"*string(i, pad=3) for i in 1:groups[:ANALOG].USED ]
                    push!(groups[:ANALOG],
                          StringParameter(NaN, NaN, false, abs(groups[:ANALOG].gid), "LABELS", :LABELS, NaN, labels, 14, "Channel labels"))
                elseif !haskey(groups[:ANALOG].DESCRIPTIONS)
                    @debug ":ANALOG is missing parameter :DESCRIPTIONS"
                elseif !haskey(groups[:ANALOG].UNITS)
                    @debug ":ANALOG is missing parameter :UNITS"
                end
            end

            if length(groups[:ANALOG].LABELS) < groups[:ANALOG].USED # Some markers don't have labels
                i = 2
                while length(groups[:ANALOG].LABELS) < groups[:ANALOG].USED
                    if haskey(groups[:ANALOG].params, Symbol("LABEL",i)) # Check for the existence of a runoff labels group
                        append!(groups[:ANALOG].LABELS, groups[:ANALOG].params[Symbol("LABEL",i)])
                    else
                        labels = [ "A"*string(i, pad=3) for i in length(groups[:ANALOG].LABELS):groups[:ANALOG].USED ]
                        append!(groups[:ANALOG].LABELS, labels)
                    end
                    i += 1
                end
            end

            if length(unique(groups[:ANALOG].LABELS)) != length(groups[:ANALOG].LABELS)
                dups = String[]
                for i in 1:groups[:ANALOG].USED
                    if !in(groups[:ANALOG].LABELS[i], dups)
                        push!(dups, groups[:ANALOG].LABELS[i])
                    else
                        m = match(r"\d+$", groups[:ANALOG].LABELS[i])

                        if m == nothing
                            groups[:ANALOG].LABELS[i] *= "2"
                            push!(dups, groups[:ANALOG].LABELS[i])
                        else
                            newlabel = groups[:ANALOG].LABELS[i][1:(m.offset - 1)]*string(parse(m.match)+1)
                            groups[:ANALOG].LABELS[i] = newlabel
                            push!(dups, groups[:ANALOG].LABELS[i])
                        end
                    end
                end
            end
        end # End if analog channels exist

    end

    nothing
end

