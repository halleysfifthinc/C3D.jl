.SUFFIXES:
.SUFFIXES: .c .o

CFLAGS = -O3 -ansi -w -fPIC
LDFLAGS = -shared

ifeq ($(OS),Windows_NT)
SHLIB_EXT = dll
CC := $(ARCH)-w64-mingw32-gcc
else ifeq ($(shell uname),Darwin)
CC = gcc
SHLIB_EXT = dylib
else
SHLIB_EXT = so
CC = gcc
endif

LIB_NAME := libvaxdata-$(ARCH).$(SHLIB_EXT)
PREFIX = usr
LIBDIR := $(PREFIX)/include
DESTDIR := $(PREFIX)/lib/

_OBJS = from_vax_i2.o       from_vax_i2_.o      from_vax_i4.o       \
       from_vax_i4_.o      from_vax_r4.o       from_vax_r4_.o      \
       from_vax_d8.o       from_vax_d8_.o      from_vax_g8.o       \
       from_vax_g8_.o      to_vax_i2.o         to_vax_i2_.o        \
       to_vax_i4.o         to_vax_i4_.o        to_vax_r4.o         \
       to_vax_r4_.o        to_vax_d8.o         to_vax_d8_.o        \
       to_vax_g8.o         to_vax_g8_.o        is_little_endian.o  \
       is_little_endian_.o

OBJS := $(addprefix $(LIBDIR)/$(ARCH)/, $(_OBJS))


VPATH = src/libvaxdata/src

all: $(DESTDIR)$(LIB_NAME)

$(DESTDIR)$(LIB_NAME): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

$(LIBDIR)/$(ARCH)/%.o: %.c | $(LIBDIR)/$(ARCH)
	$(CC) $(CFLAGS) -c $^ -o $@

$(LIBDIR)/$(ARCH):
	mkdir $(LIBDIR)/$(ARCH)

.PHONY: clean

clean:
	$(RM) $(DESTDIR)$(LIB_NAME) $(OBJS)
