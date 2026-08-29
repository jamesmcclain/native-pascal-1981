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
PROXY_BIN := $(BIN_DIR)/pascal1981-proxy
RUNTIME_LIB := runtime/build/libpascalrt.a
RUNTIME_SRCS := $(wildcard runtime/*.c runtime/*.h) runtime/Makefile
STAGES := lexer parser typechecker codegen
# Every stage splices jsonutil.inc, so a change to the interface must rebuild
# all of them -- $INCLUDE is textual, and make cannot see through it.
STAGE_SRCS := src/jsonutil.pas src/jsonutil.inc scripts/build-stage.sh
# codegen is a composition root over these units: it splices every one of
# their .inc interfaces and links every .pas as a component object. Listed
# lowest layer first -- the same order scripts/build-stage.sh compiles and
# links them in. Attached to the codegen targets alone, below, rather than to
# every stage.
CODEGEN_UNITS := cg_base cg_util cg_types cg_symbols cg_expr_shape cg_expr_sets cg_expr_support cg_expr_literals cg_expr cg_io cg_stmt cg_decl
CODEGEN_SRCS := $(foreach u,$(CODEGEN_UNITS),src/$(u).pas src/$(u).inc)
# typechecker follows the same separately-compiled unit pattern as codegen.
# Its list is also lowest layer first and must match scripts/build-stage.sh.
TYPECHECKER_UNITS := tc_base tc_types tc_expr tc_stmt tc_decl
TYPECHECKER_SRCS := $(foreach u,$(TYPECHECKER_UNITS),src/$(u).pas src/$(u).inc)
# parser follows the same separately-compiled unit pattern. Its list is
# lowest layer first and must match scripts/build-stage.sh. ps_expr also owns
# type parsing: SIZEOF(type) reaches types from factors while ADS(space) reaches
# expressions from types, so the 1981 unit DAG cannot split that SCC further.
PARSER_UNITS := ps_base ps_expr ps_stmt ps_decl
PARSER_SRCS := $(foreach u,$(PARSER_UNITS),src/$(u).pas src/$(u).inc)
GEN1_BINS := $(addprefix $(BUILD_DIR)/gen1/,$(STAGES))
GEN2_BINS := $(addprefix $(BUILD_DIR)/gen2/,$(STAGES))
GEN3_BINS := $(addprefix $(BUILD_DIR)/gen3/,$(STAGES))
GEN4_BINS := $(addprefix $(BUILD_DIR)/gen4/,$(STAGES))
BOOTSTRAP_BINS := $(addprefix $(BIN_DIR)/,$(STAGES))
FIXED_POINT := $(BUILD_DIR)/.fixed-point-verified

.PHONY: all runtime driver bootstrap beautify clean cleaner cleanest tidy test test-driver test-native test-proxy test-gpu test-reference-parity test-elisp test-bootstrap

all: runtime driver bootstrap $(PROXY_BIN)

runtime: $(RUNTIME_LIB)

$(RUNTIME_LIB): $(RUNTIME_SRCS)
	$(MAKE) -C runtime

driver: $(DRIVER_BIN)

$(DRIVER_BIN): src/driver.pas $(STAGE_SRCS) $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@
	ln -sf pascal1981-native $(DRIVER_ALIAS)

$(ASTCOMPARE_BIN): src/astcompare.pas $(STAGE_SRCS) $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@

# The completion proxy. Like astcompare, a standalone program built by the
# gen4 fixed point rather than a bootstrap stage, so it is free to use units
# the reference compiler has never seen.
$(PROXY_BIN): src/proxy.pas src/bytebuf.pas src/bytebuf.inc src/argparse.pas src/argparse.inc src/jsonx.pas src/jsonx.inc src/netsock.pas src/netsock.inc src/httpio.pas src/httpio.inc src/proxycore.pas src/proxycore.inc $(STAGE_SRCS) $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

bootstrap: $(BOOTSTRAP_BINS)

$(BUILD_DIR)/gen1/%: src/%.pas $(STAGE_SRCS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen1
	./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR)/gen2/%: src/%.pas $(STAGE_SRCS) $(GEN1_BINS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen2
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen1/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen1/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen1/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen1/codegen)" ./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR)/gen3/%: src/%.pas $(STAGE_SRCS) $(GEN2_BINS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen3
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen2/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen2/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen2/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen2/codegen)" ./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

$(BUILD_DIR)/gen4/%: src/%.pas $(STAGE_SRCS) $(GEN3_BINS) $(RUNTIME_LIB) | $(BUILD_DIR)/gen4
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen3/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen3/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen3/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen3/codegen)" ./scripts/build-stage.sh $< $@ $(if $(filter codegen,$*),$(LLVM_LINK_FLAGS))

# Extra prerequisites for the codegen stage only. A recipe-less rule augments
# the pattern rules above rather than overriding them.
$(BUILD_DIR)/gen1/codegen $(BUILD_DIR)/gen2/codegen $(BUILD_DIR)/gen3/codegen $(BUILD_DIR)/gen4/codegen: $(CODEGEN_SRCS)
$(BUILD_DIR)/gen1/typechecker $(BUILD_DIR)/gen2/typechecker $(BUILD_DIR)/gen3/typechecker $(BUILD_DIR)/gen4/typechecker: $(TYPECHECKER_SRCS)
$(BUILD_DIR)/gen1/parser $(BUILD_DIR)/gen2/parser $(BUILD_DIR)/gen3/parser $(BUILD_DIR)/gen4/parser: $(PARSER_SRCS)

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
	rm -rf bin/lexer bin/parser bin/typechecker bin/codegen bin/astcompare bin/pascal1981-proxy bin/pascal1981-native bin/pascal1981
	$(MAKE) -C runtime cleaner

cleanest: cleaner
	rm -rf .pytest_cache

test: test-native test-proxy
	./tests/test_precommit_hook.sh

# The zero-Python subset of `test`: driver, golden-file behavioral, and
# IR/PTX-text directive tests. It does not run pytest or Python.
test-driver: $(DRIVER_BIN)
	./tests/driver.sh

test-native: test-driver $(ASTCOMPARE_BIN) $(PROXY_BIN)
	./tests/run.sh
	./tests/checklit.sh
	./tests/depth.sh
	./tests/astcompare.sh

# Differential conformance for the completion proxy: the same corpus of raw
# HTTP requests replayed against the Pascal port and against the Python
# implementation it replaces, compared byte for byte. Needs Python for the
# stub backend, so it is not part of test-driver's zero-Python subset.
test-proxy: $(PROXY_BIN)
	./tests/proxy/run.sh $(PROXY_BIN)
	./tests/proxy/transforms_check.py
	./tests/proxy/oneshot.sh
	$(PYTHON) -m pytest tests/proxy/test_corpus.py -q
	./tests/proxy/corpus_smoke.py
	./tests/proxy/corpus_smoke.py --reference

# Run the real-GPU CUDA integration test. The runner exits successfully with a
# clear skip reason when its hardware or toolchain prerequisites are absent.
test-gpu: bootstrap
	./tests/gpu_orchestration.sh

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
