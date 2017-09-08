A set of C3D test files - all files are Intel/MS-DOS, INT format data.

These files can be used to check that your C3D compatible application
reads the correct values from the C3D header in block 1 of the C3D
file.  All files contain identical 3D and parameter data - the parameter
POINT:DATA_START is set to the correct value (20) in test files B, C
and D.  All header values are accurate.

Note that tests with many commercial applications that "claim" to be
C3D compliant will fail to read TESTB, TESTC, and TESTD files.  Any
application failing to read these files is not using the C3D header
record information correctly.

EB015PI.C3D
	A standard C3D file with the Header at block #1, a single
	parameter record start at block #2.  The 3D data record
	starts at block #11.

TESTAPI.C3D
	As above but with a standard C3D parameter header record
	where bytes 1,2 of the parameter header are 0x00h.

TESTBPI.C3D
	Derived from TESTAPI.C3D, this C3D file has Header at
	block #1, but the parameter record starts at block #11,
	and the 3D data record starts at block #20.  All header
	pointers are set to indicate the correct record locations.
	This simulates an extra data block (0xFFh) located before
	the parameter section.

TESTCPI.C3D
	Derived from TESTAPI.C3D, this C3D file has Header at
	block #1, the parameter record starts at block #2, but an
	addition record of 9 blocks exists following the parameter
	record, the 3D data record starts at block #20.  All header
	pointers are set to indicate the correct record locations.
	This simulates an extra data block (0xFFh) located after the
	parameter section.

TESTDPI.C3D
	Derived from TESTAPI.C3D, this C3D file has Header at
	block #1, the parameter record starts at block #7, and the
	3D data record starts at block #20.  All header pointers
	are set to indicate the correct record locations.
	This simulates an extra data block (0xFFh) located prior to
	the parameter section together with a second extra data
	block following the parameter section and before the start
	of 3D data.

