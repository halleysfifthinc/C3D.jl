module C3D

using VaxData, PrecompileTools, LazyArtifacts, Dates, DelimitedFiles

export readc3d, writec3d, numpointframes, numanalogframes, writetrc

export C3DFile

include("endian.jl")
include("parameters.jl")
include("groups.jl")
include("header.jl")

struct C3DFile{END<:AbstractEndian}
    name::String
    header::Header{END}
    groups::Dict{Symbol, Group}
    point::Dict{String, Array{Union{Missing, Float32},2}}
    residual::Dict{String, Array{Union{Missing, Float32},1}}
    cameras::Dict{String, Vector{UInt8}}
    analog::Dict{String, Array{Float32,1}}
end

include("read.jl")
include("validate.jl")
include("write.jl")
include("util.jl")

struct DuplicateMarkerError
    msg::String
end

function Base.showerror(io::IO, err::DuplicateMarkerError)
    println(io, "DuplicateMarkerError: ", err.msg)
end

function C3DFile(name::String, header::Header, groups::Dict{Symbol,Group},
                 point::AbstractArray, residuals::AbstractArray, analog::AbstractArray;
                 missingpoints::Bool=true, strip_prefixes::Bool=false)
    fpoint = Dict{String,Matrix{Union{Missing, Float32}}}()
    fresiduals = Dict{String,Vector{Union{Missing, Float32}}}()
    cameras = Dict{String,Vector{UInt8}}()
    fanalog = Dict{String,Vector{Float32}}()

    l = size(point, 1)
    allpoints = 1:l
    numpts = groups[:POINT][Int, :USED]

    ptlabel_keys = get_multipled_parameter_names(groups, :POINT, :LABELS)
    pt_labels = Iterators.flatten(
        groups[:POINT][Vector{String}, label] for label in ptlabel_keys
        )

    if strip_prefixes
        if haskey(groups, :SUBJECTS) && groups[:SUBJECTS][Int, :USES_PREFIXES] == 1
            rgx = Regex(
                "("*
                    join(groups[:SUBJECTS][Vector{String}, :LABEL_PREFIXES], '|')*
                ")(?<label>\\w*)")
        else
            rgx = r":(?<label>\w*)"
        end
    end

    nolabel_count = 1
    if !iszero(numpts)
        invalidpoints = Vector{Bool}(undef, size(point, 1))
        calculatedpoints = Vector{Bool}(undef, size(point, 1))
        goodpoints = Vector{Bool}(undef, size(point, 1))

        for (idx, ptname) in enumerate(pt_labels)
            idx > numpts && break # can't slice Iterators.flatten
            og_ptname = ptname
            stripped_ptname = ""
            if strip_prefixes
                m = match(rgx, ptname)
                if !isnothing(m) && !isnothing(m[:label])
                    ptname = m[:label]
                    stripped_ptname = ptname
                end
            end
            if isempty(ptname)
                ptname = "M"*string(nolabel_count, pad=3)
                nolabel_count += 1
            end

            # don't dedup stripped names; we don't assume uniqueness of suffixes (aka marker
            # names) because there can be multiple subjects using the same marker set
            if isempty(stripped_ptname) && ptname ∈ keys(fpoint)
                # append "_$(duplicate count)" while making sure not to duplicate an
                # existing marker name (unlikely)
                cnt = 2
                while ptname*"_$cnt" ∈ keys(fpoint); cnt+=1 end
                ptname *= "_$cnt"
                dedupped_ptname = ptname
                @warn "Duplicate marker label detected (\"$(og_ptname)\"). Duplicate renamed to \"$dedupped_ptname\"."
            end
            ptname ∉ keys(fpoint) || throw(DuplicateMarkerError(
                "Markers labels must be unique but found duplicate marker label \"$ptname\""*
                if !isempty(stripped_ptname)
                    " (originally \"$(og_ptname)\" before stripping subject prefixes)"
                else
                    "" # shouldn't be reachable?
                end
                ))

            fpoint[ptname] = point[:,((idx-1)*3+1):((idx-1)*3+3)]
            fresiduals[ptname] = residuals[:,idx]
            cameras[ptname] = ((convert.(Int32, @view(residuals[:,idx])) .>> 8) .& 0xff) .% UInt8
            invalidpoints .= convert.(Int32, fresiduals[ptname]) .% Int16 .< 0
            calculatedpoints .= iszero.(fresiduals[ptname])
            goodpoints .= .~(invalidpoints .| calculatedpoints)
            fresiduals[ptname][goodpoints] = calcresiduals(fresiduals[ptname][goodpoints], abs(groups[:POINT][Float32, :SCALE]))

            if missingpoints
                fpoint[ptname][invalidpoints, :] .= missing
                fresiduals[ptname][invalidpoints] .= missing
                fresiduals[ptname][calculatedpoints] .= 0.0f0
            end
        end
    end

    anlabel_keys = collect(filter(keys(groups[:ANALOG])) do k
        contains(string(k), r"^LABELS\d*")
    end)
    sort!(anlabel_keys; by=_naturalsortby)
    an_labels = Iterators.flatten(
        groups[:ANALOG][Vector{String}, label] for label in anlabel_keys
        )
    numanalogs = groups[:ANALOG][Int, :USED]

    nolabel_count = 1
    if !iszero(numanalogs)
        for (idx, name) in enumerate(an_labels)
            idx > numanalogs && break # can't slice Iterators.flatten
            og_name = name
            if isempty(name)
                name = "A"*string(nolabel_count, pad=3)
                nolabel_count += 1
            end
            if name ∈ keys(fanalog)
                # append "_$(duplicate count)" while making sure not to duplicate an
                # existing marker name (unlikely)
                cnt = 2
                while name*"_$cnt" ∈ keys(fanalog); cnt+=1 end
                name *= "_$cnt"
                dedupped_name = name
                @warn "Duplicate analog signal label detected (\"$(og_name)\"). Duplicate renamed to \"$dedupped_name\"."
            end

            fanalog[name] = analog[:, idx]
        end
    end

    return C3DFile(name, header, groups, fpoint, fresiduals, cameras, fanalog)
end

C3DFile(fn::AbstractString) = readc3d(string(fn))

numpointframes(f::C3DFile) = numpointframes(f.groups)

function numpointframes(groups::Dict{Symbol,Group})::Int
    numframes::Int = groups[:POINT][Int, :FRAMES]
    if haskey(groups[:POINT], :LONG_FRAMES)
        if typeof(groups[:POINT][:LONG_FRAMES]) <: Vector{Int16}
            pointlongframes = only(reinterpret(Int32, groups[:POINT][Vector{Int16}, :LONG_FRAMES]))
        else
            pointlongframes = convert(Int, groups[:POINT][Float32, :LONG_FRAMES])
        end
        if numframes ≤ typemax(UInt16) && numframes != pointlongframes
            @debug "file may be misformatted. POINT:FRAMES ($numframes) != POINT:LONG_FRAMES ($pointlongframes)"
        end
        numframes = pointlongframes
    end
    if haskey(groups, :TRIAL) && haskey(groups[:TRIAL], :ACTUAL_START_FIELD) &&
        haskey(groups[:TRIAL], :ACTUAL_END_FIELD)
        trial_startend_field = only(reinterpret(UInt32,
                                    groups[:TRIAL][Vector{Int16}, :ACTUAL_END_FIELD])) -
                               only(reinterpret(UInt32,
                                    groups[:TRIAL][Vector{Int16}, :ACTUAL_START_FIELD])) + 1
        if numframes ≤ typemax(UInt16) && numframes != trial_startend_field
            @debug "file may be misformatted. POINT:FRAMES ($numframes) != POINT:LONG_FRAMES ($trial_startend_field)"
        end
        numframes = trial_startend_field
    end
    return numframes
end

function numanalogframes(f::C3DFile)
    if iszero(f.groups[:ANALOG][Int, :USED])
        return 0
    else
        aspf = convert(Int, f.groups[:ANALOG][Float32, :RATE] /
                            f.groups[:POINT][Float32, :RATE])
        return numpointframes(f)*aspf
    end
end

endianness(f::C3DFile{END}) where END = END

groups(f::C3DFile) = collect(values(f.groups))
parameters(f::C3DFile) = collect(Iterators.flatten((values(group) for group in groups(f))))

function Header{END}(f::C3DFile{OEND}) where {END<:AbstractEndian,OEND<:AbstractEndian}
    h = f.header
    paramptr::UInt8 = 2
    datafmt::UInt8 = 0x50
    npoints::UInt16 = f.groups[:POINT][Int, :USED]
    pointrate::Float32 = get(f.groups[:POINT], (Float32, :RATE), h.pointrate)
    if isinteger(get(f.groups[:ANALOG], (Float32, :RATE), pointrate)/pointrate)
        aspf = convert(UInt16, get(f.groups[:ANALOG], (Float32, :RATE), pointrate)/pointrate)
    else
        throw(ArgumentError("ANALOG:RATE is not an integer multiple of POINT:RATE; writing out-of-spec C3DFiles is not supported"))
    end
    ampf::UInt16 = aspf*f.groups[:ANALOG][Int, :USED]

    datastart::UInt8 = 2+round(sum(writesize, Iterators.flatten((groups(f), parameters(f))))/512, RoundUp)

    return Header{END}(paramptr, datafmt, npoints, ampf, h.fframe, h.lframe, h.maxinterp,
        h.scale, datastart, aspf, pointrate, h.res1, h.labeltype, h.numevents, h.res2,
        h.evtimes, h.evstat, h.res3, h.evlabels, h.res4)
end
Header(f::C3DFile{END}) where END = Header{END}(f)

function Base.show(io::IO, f::C3DFile)
    dispwidth = textwidth(f.name) + 11
    cols = displaysize(io)[2] - 11
    pathcomps = splitpath(f.name)

    if get(io, :limit, false) || dispwidth > cols
        i = first(pathcomps) == "/" ? 2 : 1

        @views while sum(textwidth, pathcomps[i:end]) + length(pathcomps) - i + 3 > cols &&
          i+1 < length(pathcomps)
            i += 1
        end

        if i > 1
            pathcomps[i] = "…/"
            @views name = joinpath(pathcomps[i:end])
        else
            @views name = joinpath(pathcomps[i+1:end])
        end
    else
        name = f.name
    end

    print(io, "C3DFile(\"", name, "\")")
end

const RST = "\e[39m"
const GRY = "\e[37m"

function Base.show(io::IO, ::MIME"text/plain", f::C3DFile)
    nframes = numpointframes(f)
    fs = round(Int, f.groups[:POINT][Float32, :RATE])

    rem_frames = round(Int, rem(nframes, fs))
    rem_str = rem_frames > 0 ? '+'*lpad(rem_frames, ndigits(fs - 1), '0') : ""
    nframes -= rem_frames

    tim = canonicalize(Dates.CompoundPeriod(Second(fld(nframes,fs))))

    println(io, f)
    print(io, "  Duration: ")
    if nframes == 0 # Duration less than a second
        print(io, "0")
    else
        join(io, [Dates.value(first(tim.periods));
            lpad.(Dates.value.(Iterators.rest(tim.periods, 2)), 2, '0')], ':')
    end
    print(io, rem_str, " $GRY")
    if nframes > 0 && maximum(tim.periods) isa Hour
        print(io, "hh:mm:ss")
    elseif nframes > 0 && maximum(tim.periods) isa Minute
        print(io, "mm:ss")
    else
        print(io, nframes > 0 ?
            's'^ndigits(Dates.value(first(filter(x -> x isa Second, tim.periods)))) : "s")
    end
    if rem_frames > 0
        print(io, "+", 'f'^ndigits(fs-1), "$RST\n  ")
    else
        print(io, "$RST\n  ")
    end

    if f.groups[:POINT][:USED] > 0
        print(io, f.groups[:POINT][Int, :USED], "$GRY points$RST ",
            "@ $(round(Int, fs))$GRY Hz$RST")
    end
    if f.groups[:ANALOG][:USED] > 0
        if f.groups[:POINT][:USED] > 0
            print(io, "; ")
        end
        print(io, f.groups[:ANALOG][Int, :USED], "$GRY analog channels$RST ",
              "@ $(round(Int, f.groups[:ANALOG][:RATE]))$GRY Hz$RST")
    end
end

@setup_workload begin
    path, io = mktemp()
    close(io)
    fn1 = joinpath(artifact"sample01", "Eb015pr.c3d")
    fn2 = joinpath(artifact"sample01", "Eb015pi.c3d")
    @compile_workload begin
        f = readc3d(fn1)
            readc3d(fn2)
        show(devnull, f)
        show(devnull, MIME("text/plain"), f)
        writetrc(path, f)
        writec3d(path, f)
    end
end

end # module
