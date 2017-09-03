################################################################################
#                                                                              #
# makefile.linux - Make library of functions for reading and writing VAX       #
#                  format data for Linux.                                      #
#                                                                              #
# Shell command syntax: make -f makefile.linux \                               #
#                            [ CC="c_compiler" ] \                             #
#                            [ CFLAGS="c_compiler_flags" ] \                   #
#                            [ all | libvaxdata | test | clean ]               #
#                                                                              #
#                                                                              #
# Author:      Lawrence M. Baker                                               #
#              U.S. Geological Survey                                          #
#              345 Middlefield Road  MS977                                     #
#              Menlo Park, CA  94025                                           #
#              baker@usgs.gov                                                  #
#                                                                              #
# Citation:    Baker, L.M., 2005, libvaxdata: VAX Data Format Conversion       #
#                 Routines: U.S. Geological Survey Open-File Report 2005-1424, #
#                 v1.1 (http://pubs.usgs.gov/of/2005/1424/).                   #
#                                                                              #
#                                                                              #
#                                 Disclaimer                                   #
#                                                                              #
# Although  this  program has been used by the USGS, no warranty, expressed or #
# implied, is made by the USGS or the  United  States  Government  as  to  the #
# accuracy  and  functioning  of the program and related program material, nor #
# shall the  fact  of  distribution  constitute  any  such  warranty,  and  no #
# responsibility is assumed by the USGS in connection therewith.               #
#                                                                              #
#                                                                              #
# Modification History:                                                        #
#                                                                              #
#  2-Sep-2005  L. M. Baker      Original version (from make.libvfbb).          #
#  5-Oct-2005  L. M. Baker      Use custom compile rule for is_little_endian.  #
# 30-Jan-2010  L. M. Baker      Add test program.                              #
#                                                                              #
################################################################################

.SUFFIXES:
.SUFFIXES: .c .o .so

# GNU C
# -O3 (highest level of optimization) -ansi (strict ANSI)
CC     = gcc
CFLAGS = -O3 -ansi -w -fPIC
LDFLAGS = -shared

LIB_NAME = libvaxdata.so
PREFIX = usr
LIBDIR = $(PREFIX)/include/
DESTDIR = $(PREFIX)/lib/

_OBJS = from_vax_i2.o       from_vax_i2_.o      from_vax_i4.o       \
       from_vax_i4_.o      from_vax_r4.o       from_vax_r4_.o      \
       from_vax_d8.o       from_vax_d8_.o      from_vax_g8.o       \
       from_vax_g8_.o      from_vax_h16.o      from_vax_h16_.o     \
       to_vax_i2.o         to_vax_i2_.o        to_vax_i4.o         \
       to_vax_i4_.o        to_vax_r4.o         to_vax_r4_.o        \
       to_vax_d8.o         to_vax_d8_.o        to_vax_g8.o         \
       to_vax_g8_.o        to_vax_h16.o        to_vax_h16_.o       \
       is_little_endian.o  is_little_endian_.o

OBJS = $(addprefix $(LIBDIR), $(_OBJS))


VPATH = src/libvaxdata/src/

all: $(DESTDIR)$(LIB_NAME)

$(DESTDIR)$(LIB_NAME): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

$(LIBDIR)from_vax_i2.o: $(VPATH)from_vax_i2.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_i2_.o: $(VPATH)from_vax_i2_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_i4.o: $(VPATH)from_vax_i4.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_i4_.o: $(VPATH)from_vax_i4_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_r4.o: $(VPATH)from_vax_r4.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_r4_.o: $(VPATH)from_vax_r4_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_d8.o: $(VPATH)from_vax_d8.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_d8_.o: $(VPATH)from_vax_d8_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_g8.o: $(VPATH)from_vax_g8.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_g8_.o: $(VPATH)from_vax_g8_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_h16.o: $(VPATH)from_vax_h16.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)from_vax_h16_.o: $(VPATH)from_vax_h16_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_i2.o: $(VPATH)to_vax_i2.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_i2_.o: $(VPATH)to_vax_i2_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_i4.o: $(VPATH)to_vax_i4.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_i4_.o: $(VPATH)to_vax_i4_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_r4.o: $(VPATH)to_vax_r4.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_r4_.o: $(VPATH)to_vax_r4_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_d8.o: $(VPATH)to_vax_d8.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_d8_.o: $(VPATH)to_vax_d8_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_g8.o: $(VPATH)to_vax_g8.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_g8_.o: $(VPATH)to_vax_g8_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_h16.o: $(VPATH)to_vax_h16.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)to_vax_h16_.o: $(VPATH)to_vax_h16_.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)is_little_endian.o: $(VPATH)is_little_endian.c
	$(CC) $(CFLAGS) -c -o $@ $^

$(LIBDIR)is_little_endian_.o: $(VPATH)is_little_endian_.c
	$(CC) $(CFLAGS) -c -o $@ $^

.PHONY: clean
clean:
	$(RM) $(DESTDIR)$(LIB_NAME) $(OBJS)
