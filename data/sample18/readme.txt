The C3D file contains a corrupted parameter section and may 
cause some applications to crash if they assume that the 
parameter section is correctly formatted.

The problem in this file is that there seems to be an "empty"
group which has a name with length=9, but actually contains no
data. This is the group which is reporting a zero offset of -1.
Strictly speaking when all the groups/parameters are done, the
next byte should have a zero value.

