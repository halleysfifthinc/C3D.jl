struct ValidateError <: Exception end

struct MissingGroupsError <: Exception
    groups::Vector{Symbol}
end

MissingGroupsError(group::Symbol) = MissingGroupsError([group])
MissingGroupsError(groups::NTuple{N,Symbol}) where N = MissingGroupsError(collect(groups))

function Base.showerror(io::IO, err::MissingGroupsError)
    print(io, "Required group(s) :")
    join(io, err.groups, ", :")
    print(io, " are missing")
end

struct MissingParametersError <: Exception
    group::Symbol
    parameters::Vector{Symbol}
end

MissingParametersError(group, parameter::Symbol) = MissingParametersError(group, [parameter])
MissingParametersError(group, parameter::NTuple{N,Symbol}) where N = MissingParametersError(group, collect(parameter))

function Base.showerror(io::IO, err::MissingParametersError)
    print(io, "Group :$(err.group) is missing required parameter(s) :")
    join(io, err.parameters, ", :")
end

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
            groups[:ANALOG] = Group(0, 6, false, 0, "ANALOG", :ANALOG, 0, 22,
                "Analog data parameters")
            groups[:ANALOG].params[:USED] = Parameter(0, 5, false, 0, "USED", :USED, 0, 30,
                "Number of analog channels used", ScalarParameter(zero(Int16)))
        else
            d = setdiff(rgroups, keys(groups))
            throw(MissingGroupsError(d))
        end
    end

    # Validate the :POINT group
    pointkeys = keys(groups[:POINT].params)
    if !(rpoint ⊆ pointkeys)
        # The minimum set of parameters in :POINT is rpoint
        d = setdiff(rpoint, pointkeys)
        throw(MissingParametersError(:POINT, d))
    end

    # Fix the sign for any point parameters that are likely to need it
    for (group, param) in pointsigncheck
        if any(signbit, groups[group].params[param].payload.data)
            groups[group].params[param] = unsigned(groups[group].params[param])
        end
    end

    # Validate the :ANALOG group
    analogkeys = keys(groups[:ANALOG].params)
    if !haskey(groups[:ANALOG], :USED)
        throw(MissingParametersError(:ANALOG, :USED))
    end

    POINT_USED = groups[:POINT][Int, :USED]
    ANALOG_USED = groups[:ANALOG][Int, :USED]
    if POINT_USED != 0 # There are markers
        # If there are markers, the additional set of required parameters is ratescale
        if !(ratescale ⊆ pointkeys)
            if !(:RATE ∈ pointkeys) && ANALOG_USED == 0
                # If there is no analog data, POINT:RATE isn't technically required
            else
                d = setdiff(ratescale, pointkeys)
                throw(MissingParametersError(:POINT, d))
            end
        end

        if !(descriptives ⊆ pointkeys) # Check that the descriptive parameters exist
            if !haskey(groups[:POINT], :LABELS)
                # While the C3D file can technically be read in the absence of a LABELS
                # parameter, this implementation requires LABELS (for indexing)
                @debug ":POINT is missing parameter :LABELS"
                labels = [ "M"*string(i, pad=3) for i in 1:POINT_USED ]
                groups[:POINT].params[:LABELS] = Parameter(0, 0, false,
                    abs(groups[:POINT].gid), "LABELS", :LABELS, 0, 13,
                    "Marker labels", StringParameter(labels))
            elseif !haskey(groups[:POINT], :DESCRIPTIONS)
                @debug ":POINT is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:POINT], :UNITS)
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
                if haskey(groups[:POINT], Symbol("LABEL",i))
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

    # Further validate the :ANALOG group
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
                throw(MissingParametersError(:ANALOG, d))
            end
        elseif !(descriptives ⊆ analogkeys) # Check that the descriptive parameters exist
            if !haskey(groups[:ANALOG], :LABELS)
                @debug ":ANALOG is missing parameter :LABELS"
                labels = [ "A"*string(i, pad=3) for i in 1:ANALOG_USED ]
                groups[:ANALOG].params[:LABELS] = Parameter{StringParameter}(0, 0, false,
                    abs(groups[:ANALOG].gid), "LABELS", :LABELS, 0, 14, "Channel labels",
                    StringParameter(labels))
            elseif !haskey(groups[:ANALOG], :DESCRIPTIONS)
                @debug ":ANALOG is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:ANALOG], :UNITS)
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
                if haskey(groups[:ANALOG], Symbol("LABEL",i)) # Check for the existence of a runoff labels group
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

    missing_groups = filter(!isnothing, map(x -> match(r"GID_(\d+)_MISSING", string(x)), collect(keys(groups))))

    if !isempty(missing_groups)
        for grp in missing_groups
            if issubset(keys(groups[Symbol(grp.match)]), (:ACTUAL_START_FIELD, :ACTUAL_END_FIELD))
                if !haskey(groups, :TRIAL)
                    groups[:TRIAL] = Group(0, 5, false, tryparse(Int8, grp[1]), "TRIAL",
                        :TRIAL, 0, 0, "")
                end
                merge!(groups[:TRIAL].params, groups[Symbol(grp.match)].params)
                delete!(groups, Symbol(grp.match))
            end
        end
    end

    return nothing
end

