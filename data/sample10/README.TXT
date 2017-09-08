This is test data - both sets of C3D files have been derived from a single file and contain identical force plate data.

Updated 7th, March 2003 to correct an error in the calculation and application of the CAL_MATRIX which now multiplies the moment columns by 1000.  The previous version (incorrectly) multiplied the rows by 1000, following the documentation error in the original AMASS/ADG documentation.

TYPE-2.C3D describes the force plate as a TYPE-2 plate using only the major diagonal components of the force plate sensitivity matrix (collected on a Vicon System).
TYPE-2a.C3D describes the force plate as a TYPE-2 plate using only the major diagonal components of the force plate sensitivity matrix (collected on a Motion Analysis System).

TYPE-4.C3D describes the force plate as a TYPE-4 plate using the entire sensitivity matrix (collected on a Vicon System).
TYPE-4a.C3D describes the force plate as a TYPE-4 plate using the entire sensitivity matrix (collected on a Motion Analysis System).

TYPE-4.XLS is a spreadsheet that calculates force and moment outputs from force plate data using both TYPE-2 and TYPE-4 calculations and may be used as a referance for calculating TYPE-4 force plate outputs.  The spreadsheet also contains a copy of the force plate sensitivity matrix information (formerly in MATRIX.XLS) and uses the sensitivity matrix to generate the calibration matrix - which in turn creates the CAL_MATRIX.

MATRIX.PDF is a printable copy of the CAL_MATRIX and original sensitivity matrix information used in the sample C3D files.