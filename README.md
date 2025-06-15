<img alt="C3D.jl logo where the 'C', '3', and 'D' are in the Julialang colors of red, green, and purple" src="https://github.com/halleysfifthinc/C3D.jl/assets/7356205/4d541fe0-04a4-46c9-8228-c45c6ec48587" width=600>

[![version](https://juliahub.com/docs/General/C3D/stable/version.svg)](https://juliahub.com/ui/Packages/General/C3D)
[![pkgeval](https://juliahub.com/docs/General/C3D/stable/pkgeval.svg)](https://juliahub.com/ui/Packages/General/C3D)
[![CI](https://github.com/halleysfifthinc/C3D.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/halleysfifthinc/C3D.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/halleysfifthinc/C3D.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/halleysfifthinc/C3D.jl)
[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)

C3D is a common file format for motion capture and other biomechanics related measurement
systems (force plate data, EMG, etc). This package completely implements the [C3D file
spec](https://www.c3d.org), and can read files from all major manufacturers where they might
differ from or extend the C3D file spec.

C3D.jl is exhaustively tested against sample data found on the [C3D
website](https://www.c3d.org/sampledata.html) and can read many technically out-of-spec
files.
Please open an issue if you have a file that is not being read correctly. Pull requests welcome!

## Usage

### Reading data

Marker and analog data are accessed through the `point` and `analog` fields. Note that all
data is converted to Float32 upon reading, regardless of the original type (eg DEC types).
(See the docstring for additional keyword arguments.)

```julia
julia> # The artifacts with the test data can only be used from the `C3D.jl` directory when `LazyArtifacts` has been loaded

julia> pc_real = readc3d(artifact"sample01/Eb015pr.c3d")
C3DFile("~/.julia/artifacts/318c299a26ba07c015fa86768512b677fbb7e64c/Eb015pr.c3d")
  Duration: 9 s
  26 points @ 50 Hz; 16 analog channels @ 200 Hz

  julia> pc_real.point["LTH1"]
450×3 Array{Float32,2}:
 0.0         0.0     0.0
 0.0         0.0     0.0
 0.0         0.0     0.0
 ⋮
 1.66667  2152.67  702.917
 3.58333  2159.0   702.833
 5.0      2168.08  702.25

julia> pc_real.analog["FZ1"]
1800-element Array{Float32,1}:
 -20.832
 -21.576
 -20.832
   ⋮
 -20.088001
 -21.576
 -22.32
```

### Writing data

Write a C3D file using the `writec3d` function. The groups and parameters of a .c3d file
describe the data contained by the file. As of v0.8, there are no C3D.jl functions that
coordinate modifying a `C3DFile` object, therefore, it is your responsibility to ensure that
any modifications (adding/removing a marker or analog channel, etc) produce an
internally-consistent (i.e. groups/parameters have been correctly updated to match the
modified data, etc) file before writing.

```julia
julia> writec3d("myfile.c3d", pc_real)
307200 # number of bytes written
```

`writec3d` is exhaustively tested against the corpus of sample data from the C3D.org website
to ensure that all files that are written are functionally[^1] and/or bitwise identical[^2] to
the original at the binary file level. In all cases, the groups, parameters, and data for a
`C3DFile` that was "copied" with `writec3d` will be exactly identical to the groups,
parameters, and data from the original `C3DFile`.

[^1]: Many manufacturers include unnecessary trailing whitespace in string parameters. C3D.jl strips trailing whitespace when reading .c3d files; this results in slightly different (smaller) parameters when written to file, but the parameter data is otherwise the same.

[^2]: There are only two situations in which the binary data in the file will differ from the original file:
    1. Some manufacturers write residuals as unsigned integers; this is incorrect according to the file-spec and C3D.jl follows the spec when writing the residuals back to file. However, the actual residual data is unchanged.
    2. Limitations of [floating-point arithmetic](https://en.wikipedia.org/wiki/Floating-point_arithmetic) mean that some analog samples may not convert exactly back after un-scaling (i.e. slightly different in the file), but the scaled values are exactly identical.

#### Point residuals, invalid and calculated points

According to the C3D format documentation, invalid data points are signified by setting the
residual word to `-1.0`. This convention is respected in C3D.jl by changing the residual and
coordinates of invalid points/frames to `missing`. If your C3D files do not respect this
convention, or if you wish to ignore this for some other reason, this behavior can be
disabled by setting keyword arg `missingpoints=false` in the `readc3d` function. Convention
is to signify calculated points (e.g. filtered, interpolated, etc) by setting the residual
value to `0.0`.

```julia
julia> bball = readc3d(artifact"sample16/basketball.c3d")
C3DFile("~/.julia/artifacts/042cc43a45ace35e97473c6cf0d08e25f1c73fcb/basketball.c3d")
  Duration: 1+09 s+ff
  22 points @ 25 Hz

julia> bball.point["2003"]
34×3 Array{Union{Missing, Float32},2}:
 missing  missing  missing
 missing  missing  missing
 missing  missing  missing
  ⋮

julia> bball = readc3d("data/sample16/basketball.c3d"; missingpoints=false)
C3DFile("~/.julia/artifacts/042cc43a45ace35e97473c6cf0d08e25f1c73fcb/basketball.c3d")
  0:1+9 frames
  22 points @ 25 Hz

julia> bball.point["2003"]
34×3 Array{Union{Missing, Float32},2}:
  0.69115      0.987054    1.53009
  0.656669     1.00666     1.5854
  0.615803     1.02481     1.60467
   ⋮
```

Point residuals can be accessed using the `residual` field which is indexed by marker label.

```julia
julia> pc_real.residual["RFT2"]
450-element Array{Union{Missing, Float32},1}:
 2.0833335f0
 2.3333335f0
 1.6666667f0
  ⋮
 0.6666667f0
 1.4166667f0
 0.5833334f0
```

### Accessing C3D parameters

The parameters can be accessed through the `groups` field. Specific groups are indexed as Symbols.

```julia
julia> pc_real.groups
Dict{Symbol,C3D.Group} with 5 entries:
  :POINT          => Symbol[:DESCRIPTIONS, :RATE, :DATA_START, :FRAMES, :USED, :UNITS, :Y_SCREEN, :LABELS, :X_SCREEN, :SCALE]
  :ANALOG         => Symbol[:DESCRIPTIONS, :RATE, :GEN_SCALE, :OFFSET, :USED, :UNITS, :LABELS, :SCALE]
  :FORCE_PLATFORM => Symbol[:TYPE, :ORIGIN, :ZERO, :TRANSLATION, :CORNERS, :USED, :ROTATION, :CHANNEL]
  :SUBJECT        => Symbol[:WEIGHT, :NUMBER, :HEIGHT, :DATE_OF_BIRTH, :GENDER, :PROJECT, :TARGET_RADIUS, :NAME]
  :FPLOC          => Symbol[:INT, :OBJ, :MAX]

julia> pc_real.groups[:POINT]
Group(:POINT), "3-D point parameters"
  POINT:DESCRIPTIONS::String @ (20,) ["DIST/LAT FOOT", "INSTEP", "PROX LAT FOOT", "SHANK", "SHANK", "SHANK", "SHANK", "ANKLE", "KNEE", "DISTAL FOOT", "*", "*", "*", "*", "*", "*", "*", "*", "*", "TARGET"]
  POINT:X_SCREEN::String ["+Y"]
  POINT:Y_SCREEN::String ["+Z"]
  POINT:LABELS::String @ (48,) ["RFT1", "RFT2", "RFT3", "LFT1", "LFT2", "LFT3", "RSK1", "RSK2", "RSK3", "RSK4"  …  "", "", "", "", "", "", "", "", "", ""]
  POINT:UNITS::String ["mm"]
  POINT:USED::UInt16 26
  POINT:FRAMES::UInt16 450
  POINT:SCALE::Float32 -0.0833333
  POINT:DATA_START::UInt16 11
  POINT:RATE::Float32 50.0
```

Parameter values can be accessed like this:

```julia
julia> pc_real.groups[:POINT][:USED]
26

julia> pc_real.groups[:POINT][:LABELS]
48-element Array{String,1}:
 "RFT1"
 "RFT2"
 "RFT3"
 ⋮
 ""
 ""
 ""

# Or, if you know the type (and you need the type-stability)
julia> pc_real.groups[:POINT][Int, :USED]
26

```

# Advanced: Debugging

Set the `JULIA_DEBUG` environment variable to `"C3D"` (e.g. from within Julia,
`ENV["JULIA_DEBUG"] = "C3D"`) to enable debug logging. In addition, there are two keyword
arguments to `readc3d` which may be useful if a file is error'ing when being read:
`paramsonly=true` will only read the parameter section and skip reading the data, and
`validate=false` will disable parameter validation.

```julia
julia> pc_real = readc3d("data/sample01/Eb015pr.c3d"; paramsonly=true)
Dict{Symbol,C3D.Group} with 5 entries:
  :POINT          => Symbol[:DESCRIPTIONS, :RATE, :DATA_START, :FRAMES, :USED, :UNITS, :Y_SCREEN, :LABELS, :X_SCREEN, :SCALE]
  :ANALOG         => Symbol[:DESCRIPTIONS, :RATE, :GEN_SCALE, :OFFSET, :USED, :UNITS, :LABELS, :SCALE]
  :FORCE_PLATFORM => Symbol[:TYPE, :ORIGIN, :ZERO, :TRANSLATION, :CORNERS, :USED, :ROTATION, :CHANNEL]
  :SUBJECT        => Symbol[:WEIGHT, :NUMBER, :HEIGHT, :DATE_OF_BIRTH, :GENDER, :PROJECT, :TARGET_RADIUS, :NAME]
  :FPLOC          => Symbol[:INT, :OBJ, :MAX]

julia> pc_real = readc3d("data/sample01/Eb015pr.c3d"; paramsonly=true, validate=false)
Dict{Symbol,C3D.Group} with 5 entries:
  :POINT          => Symbol[:DESCRIPTIONS, :RATE, :DATA_START, :FRAMES, :USED, :UNITS, :Y_SCREEN, :LABELS, :X_SCREEN, :SCALE]
  :ANALOG         => Symbol[:DESCRIPTIONS, :RATE, :GEN_SCALE, :OFFSET, :USED, :UNITS, :LABELS, :SCALE]
  :FORCE_PLATFORM => Symbol[:TYPE, :ORIGIN, :ZERO, :TRANSLATION, :CORNERS, :USED, :ROTATION, :CHANNEL]
  :SUBJECT        => Symbol[:WEIGHT, :NUMBER, :HEIGHT, :DATE_OF_BIRTH, :GENDER, :PROJECT, :TARGET_RADIUS, :NAME]
  :FPLOC          => Symbol[:INT, :OBJ, :MAX]
```

Please open an issue if you have a file that C3D.jl is unable to read.
