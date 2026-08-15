# Top-level Makefile for native-pascal-1981 toolchain

ifeq ($(origin CC),default)
CC          := clang
else
CC          ?= clang
endif
PYTHON      ?= python3
CFLAGS      := -O2 -Wall -Wextra
LLVM_CONFIG ?= $(shell which llvm-config 2>/dev/null || which llvm-config-20 2>/dev/null || echo llvm-config)
export CC LLVM_CONFIG PYTHON

BIN_DIR := bin
DRIVER_BIN := $(BIN_DIR)/pascal1981-native
DRIVER_ALIAS := $(BIN_DIR)/pascal1981

.PHONY: all runtime driver bootstrap beautify clean cleaner cleanest tidy test

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

cleaner: clean
	rm -rf bin/lexer bin/parser bin/typechecker bin/codegen bin/pascal1981-native bin/pascal1981
	$(MAKE) -C runtime cleaner

cleanest: cleaner
	rm -rf .pytest_cache

test: $(DRIVER_BIN)
	./tests/run.sh
	PYTHONPATH=. $(PYTHON) -m pytest tests/parity/
