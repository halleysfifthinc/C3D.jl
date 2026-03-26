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

function get_extended_parameter_names(group, param)
    rgx = Regex("^$(param)\\d*")
    params = filter!(collect(keys(group))) do k
        contains(string(k), rgx)
    end
    sort!(params; by=_naturalsortby)
    return params
end

"""
    _extended_key(base, mult) -> Symbol

Return the parameter key for the given, where the extension number is omitted for the first
parameter (e.g. `:LABELS` for mult=1, `:LABELS2` for mult=2, etc.)
"""
_extended_key(base::Symbol, mult::Int) = mult == 1 ? base : Symbol(string(base, mult))

"""
    delete_extended_param!(group, base, pos)

Delete the entry at global position `pos` from `base` or `base` extensions.

Deletion may be no-op for optional parameters if there is nothing to delete (i.e. optional
parameter is entirely missing or the specific index does not exist). Entries are cascaded
forward to maintain 255-entry alignment as needed (e.g., LABELS2[1] shifts into LABELS[255],
etc.).

Must be called before decrementing USED.
"""
function delete_extended_param!(group::Group, base::Symbol, pos::Int)
    all_keys = get_extended_parameter_names(group, base)
    @assert !isempty(all_keys) "unable to delete a parameter value for a non-existent parameter"

    mult, local_pos = fldmod1(pos, 255)

    # optional extended parameter doesn't exist (e.g. no DESCRIPTIONS2)
    mult > length(all_keys) && return
    arr = group[all_keys[mult]]

    # index in optional parameter doesn't exist (e.g. no DESCRIPTIONS for this index)
    local_pos > length(arr) && return

    deleteat!(arr, local_pos)

    # Cascade: pull first entry from each subsequent extended param
    while mult < length(all_keys)
        next_arr = group[all_keys[mult + 1]]
        isempty(next_arr) && break
        push!(arr, popfirst!(next_arr))
        arr = next_arr
        mult += 1
    end

    return
end

"""
    push_extended_param!(group, base, value)

Push `value` to the end of `group[base]` (i.e. at position `group[:USED] + 1`).

Adds a `base` parameter or extensions as needed (e.g. UNITS → UNITS2 → UNITS3).

Must be called before incrementing USED.
"""
function push_extended_param!(group::Group, base::Symbol, value, pos = group[Int, :USED] + 1)
    all_keys = get_extended_parameter_names(group, base)

    mult, local_pos = fldmod1(pos, 255)

    # Need new param(s) (e.g. LABELS → LABELS2, or LABELS itself if absent)
    if mult > length(all_keys)
        # ensure earlier parameters exist
        for m in 1:mult-1
            key = _extended_key(base, m)
            if haskey(group, key)
                if !(value isa String) && length(group[key]) < 255
                    error("The extendable $base parameter is shorter than $(name(group)):USED; non-String gaps cannot be safely filled (this file may be malformed)")
                else
                    continue
                end
            else
                group[key] = Parameter(key, "", fill("", 255); gid=gid(group))
            end
        end

        target_key = _extended_key(base, mult)
        @assert !haskey(group, target_key)

        T = if (prev_group = get(group, _extended_key(base, mult-1), nothing)) !== nothing
            eltype(prev_group)
        elseif typeof(value) <: Number
            if isinteger(value)
                value < typemax(Int16) ? Int16 : UInt16
            else
                Float32
            end
        else
            String
        end
        group[target_key] = Parameter(target_key, "", T[value]; gid=gid(group))
    else
        arr = group[all_keys[mult]]
        if length(arr) < local_pos && pos > group[Int, :USED] # Actually pushing new element
            value isa String || error("The extendable $base parameter is shorter than $(name(group)):USED; non-String gaps cannot be safely filled (this file may be malformed)")
            # some indexed parameters are optional (e.g. POINT:DESCRIPTIONS, etc) and may not
            # be as long as USED yet
            orig_len = length(arr)
            resize!(arr, local_pos)
            fill!(@view(arr[orig_len+1:end-1]), "")
            arr[local_pos] = value
        elseif local_pos == length(arr)+1 # padding too-short extendable parameter
            push!(arr, value)
        else
            arr[local_pos] = value
        end
    end

    return
end

"""
    flatten_extended_params(group, base, ::Type{T})

Return a lazy iterator over `group[:USED]` values across the overflow chain `base`,
`base2`, `base3`, …. Each non-final segment must contain exactly 255 entries (the spec
maximum per parameter); a warning is issued if a non-final segment has a different length,
as this signals a malformed file.

The `::Type{T}` argument controls the element type passed to the typed group accessor
(e.g. `String`, `Int`, `Float32`).
"""
function flatten_extended_params(group, base::Symbol, ::Type{T}) where {T}
    all_keys = get_extended_parameter_names(group, base)
    used = group[Int, :USED]
    lens = [length(group[key]) for key in all_keys]
    for (key, len) in @views zip(all_keys[1:end-1], lens[1:end-1])
        len == 255 || error("Extended parameter $key has $(length(group[key])) entries; non-final overflow segments must contain exactly 255 entries")
    end
    total = sum(lens)
    flat = Iterators.flatten(group[Vector{T}, key] for key in all_keys)

    return Iterators.take(flat, min(used, total))
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
- `subject::String=nothing`: Only write this subject's markers (assumes marker names are
  prefixed with this string)
- `prefixes::Vector{String}=nothing`: Marker label prefixes to strip if
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
    subject::Union{Nothing,String}=nothing,
    prefixes::Union{Nothing,Vector{String}}=nothing,
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
    subject::Union{Nothing,String}=nothing,
    prefixes::Union{Nothing,Vector{String}}=nothing,
    lab_orientation::AbstractMatrix{T}=eye3,
    virtual_markers::Dict{String,Matrix{U}}=Dict{String,Matrix{Float32}}()
) where {T,U}
    len = numpointframes(f)
    period = inv(f.groups[:POINT][Float64, :RATE])

    mkrnames = collect(keys(f.point))
    if !isnothing(subject)
        if haskey(f.groups, :SUBJECTS)
            any(subject .== f.groups[:SUBJECTS][Vector{String}, :NAMES]) || throw(ArgumentError("subject $subject does not exist in $f.groups[:SUBJECTS]"))
        else # try filtering markers with the default prefix anyways
            filter!(startswith(subject), mkrnames)
            if isempty(mkrnames)
                throw(ArgumentError("this file doesn't list any subjects in $f.groups[:SUBJECTS] and no markers are prefixed with $subject"))
            end
        end
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
            if !isnothing(subject)
                subi = findfirst(==(subject), f.groups[:SUBJECTS][Vector{String}, :NAMES])
                r = Regex("("*f.groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES][subi] *
                        ")(?<label>\\w*)")
                mkrnames_stripped = replace.(mkrnames, r => s"\g<label>")
            else
                r = Regex("("*join([f.groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES];
                        prefixes], '|')*")(?<label>\\w*)")
                mkrnames_stripped = replace.(mkrnames, r => s"\g<label>")
            end
        elseif !isnothing(subject) || !isnothing(prefixes)
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

    nummkr = length(mkrnames)
    numxmkr = length(virtual_markers)

    # Header
    line1 = ["PathFileType", "4", "(X/Y/Z)", basename(f.name)*'\n']
    line2 = ["DataRate", "CameraRate", "NumFrames", "NumMarkers", "Units", "OrigDataRate",
             "OrigDataStartFrame", "OrigNumFrames\n"]
    join(io, line1, delim)
    join(io, line2, delim)
    print(io, f.groups[:POINT][Float32, :RATE], delim)
    print(io, f.groups[:POINT][Float32, :RATE], delim)
    print(io, len, delim)
    print(io, length(mkrnames) + numxmkr, delim)
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
              for n in 1:(nummkr+numxmkr)), delim)
    write(io, '\n'^2)

    # Core data block
    et = if !isempty(virtual_markers)
        promote_type(Float32, T, U)
    else
        promote_type(Float32, T)
    end
    nanet = convert(et, NaN)
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

