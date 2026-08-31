"""
    deletepoint!(f::C3DFile, name::String)

Delete the point, residual, and camera data for `name` from `f`.

Non-standard parameters that reference markers (i.e. a parameter not prescribed in the
filespec that refers to a point marker by name) will generally not be updated following
deletion of a point. However, the following limited set of non-standard parameters in the
POINT group will be updated: ANGLES, FORCES, MOMENTS, POWERS.
"""
function deletepoint!(f::C3DFile, name::String)
    haskey(f.point, name) || throw(ArgumentError("point \"$name\" does not exist"))

    # Find global position of this label
    pos = _find_in_extended(f.groups[:POINT], :LABELS, name)
    @assert !isnothing(pos) "point keys and POINT:LABELS are inconsistent (this shouldn't be possible)"

    # Remove from data dicts
    delete!(f.point, name)
    delete!(f.residual, name)
    delete!(f.cameras, name)

    # Delete from parameter chains at the same global position
    delete_extended_param!(f.groups[:POINT], :LABELS, pos)
    delete_extended_param!(f.groups[:POINT], :DESCRIPTIONS, pos)

    # Decrement POINT:USED
    used = f.groups[:POINT].params[:USED].payload
    used.data -= 1

    # Tier 2: Remove from model output arrays if present
    for cat in (:ANGLES, :FORCES, :MOMENTS, :POWERS)
        if haskey(f.groups[:POINT], cat)
            cat_arr = f.groups[:POINT][cat]
            j = findfirst(==(name), cat_arr)
            if !isnothing(j)
                deleteat!(cat_arr, j)
            end
        end
    end

    return
end

"""
    deleteanalog!(f::C3DFile, name::String)

Delete the (independent) analog channel `name` from `f`.

Channels used in force plates may not be individually deleted.

See also [`deleteforceplate!`](@ref).
"""
function deleteanalog!(f::C3DFile, name::String)
    haskey(f.analog, name) || throw(ArgumentError("analog channel \"$name\" does not exist"))

    # Find global position of this label
    pos = _find_in_extended(f.groups[:ANALOG], :LABELS, name)
    @assert !isnothing(pos) "analog keys and ANALOG:LABELS are inconsistent (this shouldn't be possible)"

    # Refuse to delete channels assigned to a force plate
    if haskey(f.groups, :FORCE_PLATFORM) && haskey(f.groups[:FORCE_PLATFORM], :CHANNEL)
        fp_channel = f.groups[:FORCE_PLATFORM][:CHANNEL]
        if pos ∈ fp_channel
            throw(ArgumentError("individual analog channels assigned to force plates can't be deleted"))
        end
    end

    _deleteanalog_unchecked!(f, name, pos)
end

"""
    _remove_last_dim(arr::AbstractArray, idx::Int)

Return a copy of `arr` with slice `idx` removed along the last dimension.
"""
function _remove_last_dim(arr::AbstractVector, idx::Int)
    return arr[[i for i in eachindex(arr) if i != idx]]
end
function _remove_last_dim(arr::AbstractArray{T,N}, idx::Int) where {T,N}
    keep = [i for i in axes(arr, N) if i != idx]
    return arr[ntuple(d -> d == N ? keep : (:), Val(N))...]
end

"""
    deleteforceplate!(f::C3DFile, plate::Int)

Delete force plate `plate` from `f`, removing all its analog channels and
all associated FORCE_PLATFORM parameters (TYPE, CHANNEL, ORIGIN, CORNERS, etc.).
"""
function deleteforceplate!(f::C3DFile, plate::Int)
    haskey(f.groups, :FORCE_PLATFORM) ||
        throw(ArgumentError("no FORCE_PLATFORM group in this file"))
    fp = f.groups[:FORCE_PLATFORM]
    n_plates = fp[Int, :USED]
    1 ≤ plate ≤ n_plates ||
        throw(ArgumentError("force plate index $plate out of range (1:$n_plates)"))

    # Resolve channel indices to analog labels before modifying anything
    fp_channel = fp[:CHANNEL]
    label_keys = get_extended_parameter_names(f.groups[:ANALOG], :LABELS)
    all_labels = vcat((f.groups[:ANALOG][k] for k in label_keys)...)
    n_used = f.groups[:ANALOG][Int, :USED]

    # Collect channel names for this plate (column `plate` of CHANNEL matrix)
    ch_names = String[]
    for row in axes(fp_channel, 1)
        ch_idx = Int(fp_channel[row, plate])
        if 1 ≤ ch_idx ≤ min(n_used, length(all_labels))
            push!(ch_names, all_labels[ch_idx])
        end
    end

    # Remove the plate from all FORCE_PLATFORM array parameters
    for key in (:TYPE, :CHANNEL, :ORIGIN, :CORNERS, :ZERO, :TRANSLATION, :ROTATION,
                :CAL_MATRIX)
        haskey(fp, key) || continue
        old = fp[key]
        ndims(old) == 0 && continue
        # Plate is indexed along the last dimension for all FP array params
        size(old, ndims(old)) >= plate || continue
        fp[key] = Parameter(key, "", _remove_last_dim(old, plate); gid=gid(fp))
    end

    # Decrement FORCE_PLATFORM:USED
    fp.params[:USED].payload.data -= Int16(1)

    # Delete the analog channels (largest index first to keep positions stable)
    ch_positions = sort!([_find_in_extended(f.groups[:ANALOG], :LABELS, n)
        for n in ch_names if haskey(f.analog, n)]; rev=true)
    for pos in ch_positions
        isnothing(pos) && continue
        # Re-resolve label at this position (positions may have shifted)
        label_keys = get_extended_parameter_names(f.groups[:ANALOG], :LABELS)
        current_labels = vcat((f.groups[:ANALOG][k] for k in label_keys)...)
        name = current_labels[pos]
        _deleteanalog_unchecked!(f, name, pos)
    end

    # Remap remaining FORCE_PLATFORM:CHANNEL indices from labels to new positions
    if fp[Int, :USED] > 0
        label_keys = get_extended_parameter_names(f.groups[:ANALOG], :LABELS)
        updated_labels = vcat((f.groups[:ANALOG][k] for k in label_keys)...)
        n_used = f.groups[:ANALOG][Int, :USED]
        usable = @view updated_labels[1:min(n_used, length(updated_labels))]
        new_channel = fp[:CHANNEL]
        for i in eachindex(new_channel)
            # Channel data was saved as indices → converted to labels above, but we
            # removed the plate column, so remaining entries still hold old indices.
            # Convert old index → label → new index.
            old_idx = Int(new_channel[i])
            if 1 ≤ old_idx ≤ length(all_labels)
                label = all_labels[old_idx]
                j = findfirst(==(label), usable)
                new_channel[i] = isnothing(j) ? Int16(0) : Int16(j)
            else
                new_channel[i] = Int16(0)
            end
        end
    end

    return nothing
end

"""Remove an analog channel without checking force plate membership."""
function _deleteanalog_unchecked!(f::C3DFile, name::String, pos::Int)
    # Remove from data dict
    delete!(f.analog, name)

    # Delete from per-channel parameter chains at the same global position
    delete_extended_param!(f.groups[:ANALOG], :LABELS, pos)
    delete_extended_param!(f.groups[:ANALOG], :SCALE, pos)
    delete_extended_param!(f.groups[:ANALOG], :OFFSET, pos)

    if haskey(f.groups[:ANALOG], :DESCRIPTIONS)
        delete_extended_param!(f.groups[:ANALOG], :DESCRIPTIONS, pos)
    end
    if haskey(f.groups[:ANALOG], :UNITS)
        delete_extended_param!(f.groups[:ANALOG], :UNITS, pos)
    end
    if haskey(f.groups[:ANALOG], :GAIN)
        delete_extended_param!(f.groups[:ANALOG], :GAIN, pos)
    end

    # Decrement ANALOG:USED
    used = f.groups[:ANALOG].params[:USED].payload
    used.data -= 1

    return
end
