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

function validatec3d(header, groups)
    # The following if-else ensures the minimum set of information needed to succesfully
    # read a C3DFile

    if !haskey(groups, :POINT)
        groups[:POINT] = Group("POINT", "")
    end
    if !haskey(groups, :ANALOG)
        groups[:ANALOG] = Group("ANALOG", "")
    end

    if !(rgroups ⊆ keys(groups))
        if !haskey(groups, :ANALOG)
            groups[:ANALOG] = Group("ANALOG", "Analog data parameters")
            groups[:ANALOG].params[:USED] = Parameter("USED", "Number of analog channels used", zero(Int16); gid=groups[:ANALOG].gid)
        else
            d = setdiff(rgroups, keys(groups))
            throw(MissingGroupsError(d))
        end
    end

    # Validate the :POINT group
    pointkeys = keys(groups[:POINT].params)
    if !(rpoint ⊆ pointkeys)
        if !(:USED in pointkeys)
            groups[:POINT].params[:USED] = Parameter("USED", "", header.npoints;
                gid=groups[:POINT].gid)
        end

        if !(:FRAMES in pointkeys)
            groups[:POINT].params[:FRAMES] = Parameter("FRAMES", "", header.lframe - header.fframe + 1;
                gid=groups[:POINT].gid)
        end

        if !(:DATA_START in pointkeys)
            groups[:POINT].params[:DATA_START] = Parameter("DATA_START", "", header.datastart;
                gid=groups[:POINT].gid)
        end
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
        groups[:ANALOG].params[:USED] = Parameter("USED", "",
            iszero(header.ampf) ? 0 : header.ampf÷header.aspf; gid=groups[:ANALOG].gid)
    end

    if iszero(groups[:POINT][:DATA_START])
        groups[:POINT].params[:DATA_START].payload.data = header.datastart
    end

    POINT_USED = groups[:POINT][Int, :USED]
    ANALOG_USED = groups[:ANALOG][Int, :USED]
    if POINT_USED != 0 # There are markers
        # If there are markers, the additional set of required parameters is ratescale
        if !(ratescale ⊆ pointkeys)
            if !(:RATE ∈ pointkeys)
                groups[:POINT].params[:RATE] = Parameter("RATE", "Video sampling rate",
                    header.pointrate; gid=groups[:POINT].gid)
            end

            if !(:SCALE in  pointkeys)
                groups[:POINT].params[:SCALE] = Parameter("SCALE", "", header.scale;
                    gid=groups[:POINT].gid)
            end
        end

        if !(descriptives ⊆ pointkeys) # Check that the descriptive parameters exist
            if !haskey(groups[:POINT], :LABELS)
                # While the C3D file can technically be read in the absence of a LABELS
                # parameter, this implementation requires LABELS (for indexing)
                @debug ":POINT is missing parameter :LABELS"
                labels = [ "M"*string(i, pad=3) for i in 1:POINT_USED ]
                groups[:POINT].params[:LABELS] = Parameter("LABELS", "Marker labels",
                    labels; gid=groups[:POINT].gid)
            elseif !haskey(groups[:POINT], :DESCRIPTIONS)
                @debug ":POINT is missing parameter :DESCRIPTIONS"
            elseif !haskey(groups[:POINT], :UNITS)
                @debug ":POINT is missing parameter :UNITS"
            end
        elseif groups[:POINT].params[:LABELS] isa Parameter{ScalarParameter}
            # ie There is only one used marker (or the others are unlabeled)
            groups[:POINT].params[:LABELS] = Parameter{StringParameter}(groups[:POINT].params[:LABELS])
        end
    end # End validate :POINT

    # Further validate the :ANALOG group
    if signbit(ANALOG_USED)
        groups[:ANALOG].params[:USED] = unsigned(groups[:ANALOG].params[:USED])
    end

    if ANALOG_USED != 0 # There are analog channels
        if !(:RATE in analogkeys)
            groups[:ANALOG].params[:RATE] = Parameter("RATE", "Analog sampling rate",
                groups[:POINT][Float32, :RATE] * header.aspf; gid=groups[:ANALOG].gid)
        end

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
                groups[:ANALOG].params[:LABELS] = Parameter{StringParameter}("LABELS",
                    "Channel labels", labels; gid=groups[:ANALOG].gid)
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
    end # End if analog channels exist

    missing_groups = filter(!isnothing, map(x -> match(r"GID_(\d+)_MISSING", string(x)), collect(keys(groups))))

    if !isempty(missing_groups)
        for grp in missing_groups
            if issubset(keys(groups[Symbol(grp.match)]), (:ACTUAL_START_FIELD, :ACTUAL_END_FIELD))
                if !haskey(groups, :TRIAL)
                    groups[:TRIAL] = Group("TRIAL", ""; gid=tryparse(Int8, grp[1]))
                end
                merge!(groups[:TRIAL].params, groups[Symbol(grp.match)].params)
                delete!(groups, Symbol(grp.match))
            end
        end
    end

    return nothing
end

