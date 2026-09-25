# Makefile for pasboot, the C bootstrap translator that builds generation 1
# of the self-hosting compiler without any other Pascal compiler.
#
# Usage:
#   make            Build build/pasboot.
#   make test       Run the per-feature fixtures in tests/.
#   make clean      Remove build artifacts.

# GNU make supplies CC=cc by default; do not silently inherit it.  A caller
# may still override CC explicitly (for example, CC=gcc).
ifeq ($(origin CC),default)
CC := $(shell command -v clang 2>/dev/null || command -v gcc 2>/dev/null || echo clang)
endif
CFLAGS  := -std=c99 -O2 -Wall -Wextra -D_POSIX_C_SOURCE=200809L

BUILDDIR := build
SRCS := main.c lex.c parse.c sem.c emit.c
OBJS := $(patsubst %.c,$(BUILDDIR)/%.o,$(SRCS))

.PHONY: all test clean cleaner

all: $(BUILDDIR)/pasboot

$(BUILDDIR)/pasboot: $(OBJS) | $(BUILDDIR)
	$(CC) -o $@ $(OBJS)

$(BUILDDIR)/%.o: %.c pasboot.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

test: $(BUILDDIR)/pasboot
	./tests/run.sh

clean:
	rm -rf $(BUILDDIR)

cleaner: clean
