# Makefile for the Pascal-1981 C runtime static library.
#
# Usage:
#   make            Build the CPU-shim archive (libpascalrt_cpu.a) and
#                   the canonical alias libpascalrt.a, in build/.
#   make cuda       Build the CUDA-shim archive (libpascalrt_cuda.a).
#                   Requires the CUDA toolkit headers ($CUDA_HOME/include).
#   make both       Build both archives.
#   make clean      Remove build artifacts.
#
# The CPU and CUDA device shims define the same pas_dev_* symbols, so they
# cannot coexist in one archive. We compile the shared core once and emit one
# archive per shim. Consumers pick the archive at link time. A consumer linking
# libpascalrt_cuda.a must add -lcuda on its final link line.

CC      ?= clang
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

all: $(CPU_LIB)
	cp $(CPU_LIB) $(ALIAS_LIB)

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
