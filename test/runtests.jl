using C3D, Test, LazyArtifacts

## List of sample data archived from the C3D.org website on Dec 12, 2022
# sample00 - Current C3D samples                            https://www.c3d.org/data/Sample00.zip
# Sample01 - C3D file Test SUITE                            https://www.c3d.org/data/Sample01.zip
# Sample02 - C3D files for data format testing              https://www.c3d.org/data/Sample02.zip
# sample08 - C3D compatibility test suite                   https://www.c3d.org/data/Sample08.zip
# sample36 - C3D POINT:FRAMES test suite                    https://www.c3d.org/data/Sample36.zip
# sample07 - 16-bit analog data                             https://www.c3d.org/data/Sample07.zip
# sample10 - TYPE-2 TYPE-3 and TYPE-4 FORCE PLATE DATA      https://www.c3d.org/data/Sample10.zip
# sample12 - A very large C3D file                          https://www.c3d.org/data/Sample12.zip
# sample17 - A C3D file with 14 force plates                https://www.c3d.org/data/Sample17.zip
# sample19 - A C3D file with 34672 frames of analog data    https://www.c3d.org/data/Sample19.zip
# sample22 - Robotic 2D motion                              https://www.c3d.org/data/Sample22.zip
# sample29 - Video Game motion                              https://www.c3d.org/data/Sample29.zip
# sample31 - very LONG C3D files                            https://www.c3d.org/data/Sample31.zip
# sample34 - C3D files from a IMU based system              https://www.c3d.org/data/Sample34.zip
# sample03 - C3D files containing human gait data           https://www.c3d.org/data/Sample03.zip
# sample04 - C3D files containing human gait parameters     https://www.c3d.org/data/Sample04.zip
# sample05 - C3D file with force and EMG data               https://www.c3d.org/data/Sample05.zip
# sample23 - C3D file with custom parameters                https://www.c3d.org/data/Sample23.zip
# sample26 - Sample C3D files from Qualisys                 https://www.c3d.org/data/Sample26.zip
# sample27 - Sample gait with kyowa dengyo force plates     https://www.c3d.org/data/Sample27.zip
# sample28 - Sample gait with TYPE-1 force plates           https://www.c3d.org/data/Sample28.zip
# sample30 - Sample gait from BIOGESTA                      https://www.c3d.org/data/Sample30.zip
# sample33 - A static test C3D file                         https://www.c3d.org/data/Sample33.zip
# sample35 - ANALOG EMG data from MEGAWIN                   https://www.c3d.org/data/Sample35.zip
# sample06 - PARAMETER NAME ERRORS                          https://www.c3d.org/data/Sample06.zip
# sample09 - Integer Storage Issues                         https://www.c3d.org/data/Sample09.zip
# sample11 - Poor force plate data                          https://www.c3d.org/data/Sample11.zip
# sample13 - Parameter errors                               https://www.c3d.org/data/Sample13.zip
# sample14 - Data synchronization errors                    https://www.c3d.org/data/Sample14.zip
# sample15 - Missing Parameters                             https://www.c3d.org/data/Sample15.zip
# sample16 - Invalid data                                   https://www.c3d.org/data/Sample16.zip
# sample18 - Corrupt Parameter Section                      https://www.c3d.org/data/Sample18.zip
# sample20 - Missing Parameters                             https://www.c3d.org/data/Sample20.zip
# sample21 - Missing Parameters                             https://www.c3d.org/data/Sample21.zip
# sample24 - Empty Parameters                               https://www.c3d.org/data/Sample24.zip
# sample25 - floating-point to INTEGER conversion issues    https://www.c3d.org/data/Sample25.zip
# sample32 - Data collection errors                         https://www.c3d.org/data/Sample32.zip

include("identical.jl")
include("publicinterface.jl")
include("validate.jl")
include("bigdata.jl")
include("singledata.jl")
include("invalid.jl")
include("blanklabels.jl")
include("badformats.jl")
include("inference.jl")

