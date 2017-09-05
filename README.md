# Biomechanics Data format: C3D

[![Build Status](https://travis-ci.org/halleysfifthinc/C3D.jl.svg?branch=master)](https://travis-ci.org/halleysfifthinc/C3D.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/23iuaa8lr0eav8s4/branch/master?svg=true)](https://ci.appveyor.com/project/halleysfifthinc/c3d-jl/branch/master)
[![codecov](https://codecov.io/gh/halleysfifthinc/C3D.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/halleysfifthinc/C3D.jl)

C3D is a common output format for biomechanics data gathered using various systems (motion capture, force plate data, EMG, etc). The goal of this package is to offer full coverage of the C3D [file spec](https://www.c3d.org), as well as compatibility with files from major C3D compatible programs (Vicon Nexus, etc.)

The current corpus of test data is downloaded from the C3D [website](https://www.c3d.org/sampledata.html). 
Pull requests welcome! Pull requests containing any unusual file examples not found in the C3D sample data from the website are also welcome.

Support for DEC files is possible by the use of libvaxdata:

> Baker, L.M., 2005, libvaxdata: VAX Data Format Conversion
>     Routines: U.S. Geological Survey Open-File Report 2005-1424,
>     v1.1 (http://pubs.usgs.gov/of/2005/1424/).
