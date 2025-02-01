function _naturalsortby(x)
    m = match(r"(\d+)$", string(x))
    if isnothing(m)
        return typemin(Int)
    else
        num = m[1]
        if isnothing(num)
            return typemin(Int)
        else
            return Base.parse(Int, num)
        end
    end
end

function get_multipled_parameter_names(groups, group, param)
    rgx = Regex("^$(param)\\d*")
    params = filter(collect(keys(groups[Symbol(group)]))) do k
        contains(string(k), rgx)
    end
    sort!(params; by=_naturalsortby)
    return params
end

"loosely based on countmap (addcounts_dict!) from StatsBase"
function findduplicates(itr)
    dups = Dict{eltype(itr), Int}()
    for k in itr
        index, sh = Base.ht_keyindex2_shorthash!(dups, k)
        if index > 0
            dups.age += 1
            @inbounds dups.keys[index] = k
            @inbounds dups.vals[index] += 1
        else
            @inbounds Base._setindex!(dups, 1, k, -index, sh)
        end
    end

    filter!(((k,v),) -> v > 1, dups)
    return collect(keys(dups))
end

const eye3 = [true false false;
              false true false;
              false false true]

"""
    writetrc(filename, f; <keyword arguments>)

Write the C3DFile `f` to a .trc format at `filename`.

# Keyword arguments
- `delim::Char='\\t'`: The text delimiter to use
- `strip_prefixes::Bool=true`: Strip marker label prefixes if they exist
- `subject::String=""`: The subject (among multiple subjects) in the C3DFile to write
- `prefixes::Vector{String}=[subject]`: Marker label prefixes to strip if
  `strip_prefixes == true`
- `remove_unlabeled_markers::Bool=true`: Remove markers with empty labels, labels
  matching `r"(\\*\\d+|M\\d\\d\\d)"`
- `lab_orientation::Matrix=Matrix(I, (3,3))`: Rotation to apply to markers before writing
- `precision::Int=6`: Number of decimal places to print
- `virtual_markers::Dict{String,Matrix}`: (Optional) Virtual markers (calculated with markers
  from `f`) to write to the .trc file
"""
function writetrc(filename::String, f::C3DFile;
    delim::Char='\t',
    # TODO: Add units kwarg and predicate precision on units
    precision::Int=6,
    strip_prefixes::Bool=true,
    remove_unlabeled_markers::Bool=true,
    subject::String="",
    prefixes::Vector{String}=[subject],
    lab_orientation::AbstractMatrix{T}=eye3,
    virtual_markers::Dict{String,Matrix{U}}=Dict{String,Matrix{Float32}}()
) where {T,U}
    open(filename, "w") do io
        writetrc(io, f; delim, precision, strip_prefixes, remove_unlabeled_markers, subject,
            prefixes, lab_orientation, virtual_markers)
    end
end

function writetrc(io, f::C3DFile;
    delim::Char='\t',
    precision::Int=6,
    strip_prefixes::Bool=true,
    remove_unlabeled_markers::Bool=true,
    subject::String="",
    prefixes::Vector{String}=[subject],
    lab_orientation::AbstractMatrix{T}=eye3,
    virtual_markers::Dict{String,Matrix{U}}=Dict{String,Matrix{Float32}}()
) where {T,U}
    if subject !== ""
        if haskey(f.groups, :SUBJECTS)
            any(subject .== f.groups[:SUBJECTS][Vector{String}, :NAMES]) || throw(ArgumentError("subject $subject does not exist in $f.groups[:SUBJECTS]"))
        elseif strip_prefixes && prefixes == [subject]
            @warn "subject $subject does not exist in $f.groups[:SUBJECTS] and may not be the correct prefix"
        end
    end

    len = numpointframes(f)
    period = inv(f.groups[:POINT][Float64, :RATE])

    mkrnames = collect(keys(f.point))
    if subject !== ""
        filter!(x -> startswith(x, subject), mkrnames)
        isempty(mkrnames) && @warn "no markers matched subject $subject"
    end

    if !isdisjoint(keys(f.groups[:POINT]), (:ANGLES, :POWERS, :FORCES, :MOMENTS))
        nonmarkers = reduce(vcat,
            [ f.groups[:POINT][Vector{String}, key] for key in keys(f.groups[:POINT])
                if key ∈ (:ANGLES, :POWERS, :FORCES, :MOMENTS) ])
        filter!(!in(nonmarkers), mkrnames)
    end

    if strip_prefixes
        # Assume that LABEL_PREFIXES are used if present despite absence of USES_PREFIXES
        # prompted by a c3d file from OptiTrack Motive 2.2.0
        if haskey(f.groups, :SUBJECTS) && ((haskey(f.groups[:SUBJECTS], :USES_PREFIXES) &&
            f.groups[:SUBJECTS][Int, :USES_PREFIXES] == 1) ||
            (!haskey(f.groups[:SUBJECTS], :USES_PREFIXES) &&
            haskey(f.groups[:SUBJECTS], :LABEL_PREFIXES)))
            if subject !== ""
                subi = findfirst(==(subject), f.groups[:SUBJECTS][Vector{String}, :NAMES])
                r = Regex("("*f.groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES][subi] *
                        ")(?<label>\\w*)")
                mkrnames_stripped = replace.(mkrnames, r => s"\g<label>")
            else
                r = Regex("("*join([f.groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES];
                        prefixes], '|')*")(?<label>\\w*)")
                mkrnames_stripped = replace.(mkrnames, r => s"\g<label>")
            end
        elseif subject !== "" || prefixes !== [""]
            if any(subject .== prefixes)
                r = Regex("("*join(prefixes, '|')*")(?<label>\\w*)")
            else
                r = Regex("("*join([subject; prefixes], '|')*")(?<label>\\w*)")
            end
            mkrnames_stripped = replace.(mkrnames, r => s"\g<label>")
        else
            mkrnames_stripped = mkrnames
        end
    else
        mkrnames_stripped = mkrnames
    end

    if remove_unlabeled_markers
        ids = findall(x -> isempty(x) ||
            match(r"(\*\d+|M\d\d\d)", x) !== nothing, mkrnames)
        ids_strip = findall(x -> isempty(x) ||
            match(r"(\*\d+|M\d\d\d)", x) !== nothing, mkrnames_stripped)

        # mkrnames and mkrnames_stripped need to maintain the same order
        @assert ids == ids_strip

        deleteat!(mkrnames, ids)
        deleteat!(mkrnames_stripped, ids)
    end

    ord = sortperm(mkrnames_stripped)
    mkrnames = mkrnames[ord]
    mkrnames_stripped = mkrnames_stripped[ord]

    # Header
    line1 = ["PathFileType", "4", "(X/Y/Z)", basename(f.name)*'\n']
    line2 = ["DataRate", "CameraRate", "NumFrames", "NumMarkers", "Units", "OrigDataRate",
             "OrigDataStartFrame", "OrigNumFrames\n"]
    join(io, line1, delim)
    join(io, line2, delim)
    print(io, f.groups[:POINT][Float32, :RATE], delim)
    print(io, f.groups[:POINT][Float32, :RATE], delim)
    print(io, len, delim)
    print(io, length(mkrnames) + length(virtual_markers), delim)
    print(io, strip(f.groups[:POINT][String, :UNITS], Char(0x00)), delim)
    print(io, f.groups[:POINT][Float32, :RATE], delim)
    print(io, 1, delim)
    print(io, len, delim, '\n')

    # Header line
    write(io, string("Frame#", delim, "Time", delim))
    join(io, mkrnames_stripped, delim^3)
    print(io, delim^3)
    if !isempty(virtual_markers)
        extra_mkrnames = sort!(collect(keys(virtual_markers)))
        join(io, extra_mkrnames, delim^3)
        print(io, delim^3)
    else
        extra_mkrnames = String[]
    end
    println(io)

    # Coordinate line
    write(io, delim^2)
    join(io, (string('X', n, delim, 'Y', n, delim, 'Z', n)
              for n in 1:(length(mkrnames)+length(virtual_markers))), delim)
    write(io, '\n'^2)

    # Core data block
    et = promote_type(Float32, T, U)
    nanet = convert(et, NaN)
    nummkr = length(mkrnames)
    numxmkr = length(extra_mkrnames)
    data = Matrix{Union{Missing,et}}(undef, len, 1+3*(nummkr + numxmkr))

    data[:,1] .= range(zero(et), step=period, length=len)
    for (i, name) in enumerate(mkrnames)
        idxs = (2:4).+(i-1)*3
        data[:, idxs] .= coalesce.(f.point[name]*lab_orientation, nanet)
    end
    if !isempty(virtual_markers)
        for (i, name) in enumerate(extra_mkrnames)
            idxs = (2:4).+(i-1+nummkr)*3
            data[:, idxs] .= coalesce.(virtual_markers[name]*lab_orientation, nanet)
        end
    end

    data .= round.(data; digits=precision)
    data = Any[ 1:len data fill("", len) ]
    replace!(data, missing=>"")
    replace!(data, NaN=>"")

    writedlm(io, data, delim)

    return nothing
end

