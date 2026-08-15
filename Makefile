# Top-level Makefile for native-pascal-1981 toolchain

ifeq ($(origin CC),default)
CC          := clang
else
CC          ?= clang
endif
CFLAGS      := -O2 -Wall -Wextra
LLVM_CONFIG ?= $(shell which llvm-config 2>/dev/null || which llvm-config-20 2>/dev/null || echo llvm-config)
export CC LLVM_CONFIG

BIN_DIR := bin
DRIVER_BIN := $(BIN_DIR)/pascal1981-native
DRIVER_ALIAS := $(BIN_DIR)/pascal1981

.PHONY: all runtime driver bootstrap beautify clean tidy test

all: runtime driver bootstrap

runtime:
	$(MAKE) -C runtime

driver: $(DRIVER_BIN)

$(DRIVER_BIN): driver/main.c | $(BIN_DIR)
	$(CC) $(CFLAGS) driver/main.c -o $@
	ln -sf pascal1981-native $(DRIVER_ALIAS)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

bootstrap: runtime
	./scripts/bootstrap.sh

beautify:
	./scripts/beautify.sh

tidy: clean

clean:
	./scripts/tidy.sh
	rm -rf build

test: $(DRIVER_BIN)
	./tests/run.sh
	PYTHONPATH=. pytest tests/parity/
