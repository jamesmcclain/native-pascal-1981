# Top-level Makefile for native-pascal-1981 toolchain

ifeq ($(origin CC),default)
CC          := clang
else
CC          ?= clang
endif
PYTHON      ?= python3
CFLAGS      := -O2 -Wall -Wextra
LLVM_CONFIG ?= $(shell command -v llvm-config 2>/dev/null || command -v llvm-config-20 2>/dev/null || echo llvm-config)
LLVM_LINK_FLAGS ?= $(shell $(LLVM_CONFIG) --ldflags --libs)
export CC LLVM_CONFIG PYTHON

BIN_DIR := bin
BUILD_DIR := build
DRIVER_BIN := $(BIN_DIR)/pascal1981-native
DRIVER_ALIAS := $(BIN_DIR)/pascal1981
ASTCOMPARE_BIN := $(BIN_DIR)/astcompare
RUNTIME_LIB := runtime/build/libpascalrt.a
RUNTIME_SRCS := $(wildcard runtime/*.c runtime/*.h) runtime/Makefile
STAGES := lexer parser typechecker codegen
GEN1_BINS := $(addprefix $(BUILD_DIR)/gen1/,$(STAGES))
GEN2_BINS := $(addprefix $(BUILD_DIR)/gen2/,$(STAGES))
GEN3_BINS := $(addprefix $(BUILD_DIR)/gen3/,$(STAGES))
GEN4_BINS := $(addprefix $(BUILD_DIR)/gen4/,$(STAGES))
BOOTSTRAP_BINS := $(addprefix $(BIN_DIR)/,$(STAGES))
FIXED_POINT := $(BUILD_DIR)/.fixed-point-verified

.PHONY: all runtime driver bootstrap beautify clean cleaner cleanest tidy test test-driver test-native test-reference-parity test-elisp test-bootstrap

all: runtime driver bootstrap

runtime: $(RUNTIME_LIB)

$(RUNTIME_LIB): $(RUNTIME_SRCS)
	$(MAKE) -C runtime

driver: $(DRIVER_BIN)

$(DRIVER_BIN): src/driver.pas src/jsonutil.pas scripts/build-stage.sh $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@
	ln -sf pascal1981-native $(DRIVER_ALIAS)

$(ASTCOMPARE_BIN): src/astcompare.pas src/jsonutil.pas scripts/build-stage.sh $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

bootstrap: $(BOOTSTRAP_BINS)

$(BUILD_DIR)/gen1/%: src/%.pas src/jsonutil.pas scripts/build-stage.sh $(RUNTIME_LIB) | $(BUILD_DIR)/gen1
	./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR)/gen2/%: src/%.pas src/jsonutil.pas scripts/build-stage.sh $(GEN1_BINS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen2
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen1/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen1/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen1/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen1/codegen)" ./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR)/gen3/%: src/%.pas src/jsonutil.pas scripts/build-stage.sh $(GEN2_BINS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen3
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen2/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen2/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen2/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen2/codegen)" ./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR)/gen4/%: src/%.pas src/jsonutil.pas scripts/build-stage.sh $(GEN3_BINS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen4
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen3/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen3/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen3/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen3/codegen)" ./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR) $(BUILD_DIR)/gen1 $(BUILD_DIR)/gen2 $(BUILD_DIR)/gen3 $(BUILD_DIR)/gen4:
	mkdir -p $@

$(FIXED_POINT): $(GEN3_BINS) $(GEN4_BINS) | $(BUILD_DIR)
	cmp $(BUILD_DIR)/gen3/lexer $(BUILD_DIR)/gen4/lexer
	cmp $(BUILD_DIR)/gen3/parser $(BUILD_DIR)/gen4/parser
	cmp $(BUILD_DIR)/gen3/typechecker $(BUILD_DIR)/gen4/typechecker
	cmp $(BUILD_DIR)/gen3/codegen $(BUILD_DIR)/gen4/codegen
	touch $@

$(BIN_DIR)/%: $(BUILD_DIR)/gen4/% $(FIXED_POINT) | $(BIN_DIR)
	cp $< $@

beautify:
	./scripts/beautify.sh

tidy: clean

clean:
	./scripts/tidy.sh
	rm -rf build

cleaner: clean
	rm -rf bin/lexer bin/parser bin/typechecker bin/codegen bin/astcompare bin/pascal1981-native bin/pascal1981
	$(MAKE) -C runtime cleaner

cleanest: cleaner
	rm -rf .pytest_cache

test: test-native
	./tests/test_precommit_hook.sh

# The zero-Python subset of `test`: driver, golden-file behavioral, and
# IR/PTX-text directive tests. It does not run pytest or Python.
test-driver: $(DRIVER_BIN)
	./tests/driver.sh

test-native: test-driver $(ASTCOMPARE_BIN)
	./tests/run.sh
	./tests/checklit.sh
	./tests/depth.sh
	./tests/astcompare.sh

# Compare the native compiler stages with the Python reference implementation.
# Kept separate from `test` because it requires the reference Python toolchain.
test-reference-parity:
	PYTHONPATH=. $(PYTHON) -m pytest tests/parity/

# Run the Emacs major-mode ERT suite. Kept separate from `test` because Emacs
# is not a dependency of the compiler toolchain.
test-elisp: bootstrap
	$(MAKE) -C elisp test

# Full fixed-point regression: force a clean gen1->gen4 rebuild (not reusing
# any cached generation) and fail if gen3/gen4 aren't byte-identical. Separate
# from `test` because it's the slowest thing in the repo.
test-bootstrap:
	rm -rf $(BUILD_DIR)
	$(MAKE) bootstrap
