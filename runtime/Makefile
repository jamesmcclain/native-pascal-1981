# Makefile for the Pascal-1981 C runtime static library.
#
# Usage:
#   make            Build the CPU-shim archive (libpascalrt_cpu.a) + the
#                   back-compat alias libpascalrt.a, in build/.  No GPU/CUDA
#                   headers required.
#   make cuda       Also build the CUDA-shim archive (libpascalrt_cuda.a).
#                   Requires the CUDA toolkit headers ($CUDA_HOME/include).
#   make both       Build both archives.
#   make clean      Remove build artifacts
#
# The cpu and cuda device shims define the SAME pas_dev_* symbols, so they
# cannot coexist in one archive.  Rather than rebuild-on-switch (the old
# DEVICE_SHIM clean-rebuild dance), we compile the shared core once and emit one
# archive per shim.  Consumers pick the archive at link time; the core objects
# are never recompiled to switch devices.  A consumer linking libpascalrt_cuda.a
# must add -lcuda on its final link line.
#
# DEVICE_SHIM is still accepted for backward compatibility: `make
# DEVICE_SHIM=cuda` builds the cuda archive as libpascalrt.a, as before.

CC      := clang
CFLAGS  := -c -O2 -Wall -Wextra
AR      := ar
ARFLAGS := rcs

SRCDIR  := .
BUILDDIR:= build
CUDA_HOME ?= /usr/local/cuda

# Shared core: every .c file except the two device shims (built once, reused by
# both archives).
CORE_SRCS := $(filter-out $(SRCDIR)/cpu_device_shim.c $(SRCDIR)/cuda_launch.c,$(wildcard $(SRCDIR)/*.c))
CORE_OBJS := $(patsubst $(SRCDIR)/%.c,$(BUILDDIR)/%.o,$(CORE_SRCS))

CPU_SHIM_OBJ  := $(BUILDDIR)/cpu_device_shim.o
CUDA_SHIM_OBJ := $(BUILDDIR)/cuda_launch.o

CPU_LIB   := $(BUILDDIR)/libpascalrt_cpu.a
CUDA_LIB  := $(BUILDDIR)/libpascalrt_cuda.a
ALIAS_LIB := $(BUILDDIR)/libpascalrt.a

.PHONY: all cuda both clean cleaner

# ---- Backward-compatible DEVICE_SHIM override ------------------------------
# `make DEVICE_SHIM=cuda` builds the cuda archive as the legacy libpascalrt.a.
ifeq ($(DEVICE_SHIM),cuda)
all: $(CUDA_LIB)
	cp $(CUDA_LIB) $(ALIAS_LIB)
else
# Default: CPU archive + the back-compat alias name (libpascalrt.a == cpu).
all: $(CPU_LIB)
	cp $(CPU_LIB) $(ALIAS_LIB)
endif

cuda: $(CUDA_LIB)
both: $(CPU_LIB) $(CUDA_LIB)

$(CPU_LIB): $(CORE_OBJS) $(CPU_SHIM_OBJ) | $(BUILDDIR)
	$(AR) $(ARFLAGS) $@ $^

$(CUDA_LIB): $(CORE_OBJS) $(CUDA_SHIM_OBJ) | $(BUILDDIR)
	$(AR) $(ARFLAGS) $@ $^

# The cuda shim is the only object that needs the CUDA headers.
$(CUDA_SHIM_OBJ): $(SRCDIR)/cuda_launch.c pascalrt.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -I$(CUDA_HOME)/include -o $@ $<

$(BUILDDIR)/%.o: $(SRCDIR)/%.c pascalrt.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -o $@ $<

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

clean:
	rm -rf $(BUILDDIR)

cleaner: clean

cleanest: cleaner
