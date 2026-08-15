# Top-level Makefile for native-pascal-1981 toolchain

CC      := clang
CFLAGS  := -O2 -Wall -Wextra

BIN_DIR := bin
DRIVER_BIN := $(BIN_DIR)/pascal1981-native
DRIVER_ALIAS := $(BIN_DIR)/pascal1981

.PHONY: all runtime driver bootstrap beautify clean tidy test

all: runtime driver

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

test:
	@echo "Test suites will be executed via tests/run.sh"
	@if [ -f tests/run.sh ]; then ./tests/run.sh; fi
