A sample C3D file with a very large parameter block.  The original C3D standard permitted the DATA_START value (pointing to the start of the 3D data block) to be a signed INTEGER (values +1 to +127) thus the maximum DATA_START value expected by many applications is +127. This C3D file has a DATA_START value of 188 which exceeds the signed limit of +127.

The maximum DATA_START value for an unsigned C3D file is 255.
The maximum DATA_START value for a signed C3D file is 127.

The file also has two groups with the same name "PROCESSING" - one group contains parameters, the other group is empty - this seems to be a result of a bug in Vicon Nexus.

See the C3D website for definitions of signed, unsigned and DATA_START.

http://www.c3d.org