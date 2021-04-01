using DelimitedFiles

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
function writetrc(filename::String, f::C3DFile; delim::Char='\t', strip_prefixes::Bool=true,
                  subject::String="", prefixes::Vector{String}=[subject], precision::Int=6,
                  remove_unlabeled_markers::Bool=true, lab_orientation::AbstractMatrix{T}=eye3,
                  virtual_markers::Dict{String,Matrix{U}}=Dict{String,Matrix{Float32}}()) where {T,U}
    if subject !== ""
        if haskey(f.groups, :SUBJECTS)
            any(subject .== f.groups[:SUBJECTS][Vector{String}, :NAMES]) || throw(ArgumentError("subject $subject does not exist in $f.groups[:SUBJECTS]"))
        elseif strip_prefixes && prefixes == [subject]
            @warn "subject $subject does not exist in $f.groups[:SUBJECTS] and may not be the correct prefix"
        end
    end

    io = IOBuffer()
    len = (f.groups[:POINT][Int, :FRAMES] == typemax(UInt16)) ?
        f.groups[:POINT][Int, :LONG_FRAMES] : f.groups[:POINT][Int, :FRAMES]
    period = inv(f.groups[:POINT][Float64, :RATE])

    mkrnames = collect(keys(f.point))
    if subject !== ""
        filter!(x -> startswith(x, subject), mkrnames)
        isempty(mkrnames) && @warn "no markers matched subject $subject"
    end

    if strip_prefixes
        if haskey(f.groups, :SUBJECTS) && f.groups[:SUBJECTS][Int, :USES_PREFIXES] == 1
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
    line1 = ["PathFileType", "4", "(X/Y/Z)", basename(filename)*'\n']
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
    nummkr = length(mkrnames)
    numxmkr = length(extra_mkrnames)
    data = Matrix{Union{Missing,et}}(undef, len, 1+3*(nummkr + numxmkr))

    data[:,1] .= range(zero(et), step=period, length=len)
    for (i, name) in enumerate(mkrnames)
        data[:,(2:4).+(i-1)*3] .= coalesce.(f.point[name]*lab_orientation, convert(et, NaN))
    end
    if !isempty(virtual_markers)
        for (i, name) in enumerate(extra_mkrnames)
            data[:,(2:4).+(i-1+nummkr)*3] .= coalesce.(virtual_markers[name]*lab_orientation, convert(et, NaN))
        end
    end

    data .= round.(data; digits=precision)
    data = Any[ 1:len data fill("", len) ]
    replace!(data, missing=>"")
    replace!(data, NaN=>"")

    writedlm(io, data, delim)

    open(filename, "w") do fio
        write(fio, take!(io))
    end

    return filename
end

