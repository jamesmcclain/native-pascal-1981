# Top-level Makefile for native-pascal-1981 toolchain

ifeq ($(origin CC),default)
CC          := clang
else
CC          ?= clang
endif
CFLAGS      := -O2 -Wall -Wextra
LLVM_CONFIG ?= $(shell command -v llvm-config 2>/dev/null || command -v llvm-config-20 2>/dev/null || echo llvm-config)
LLVM_LINK_FLAGS ?= $(shell $(LLVM_CONFIG) --ldflags --libs)
export CC LLVM_CONFIG

# Parallel jobs for the tool build `make test` does before it runs suites.
BUILD_JOBS ?= 8
TEST_ENV := ./scripts/test-env.sh

BIN_DIR := bin
BUILD_DIR := build
DRIVER_BIN := $(BIN_DIR)/pascal1981-native
DRIVER_ALIAS := $(BIN_DIR)/pascal1981
ASTCOMPARE_BIN := $(BIN_DIR)/astcompare
PROXY_BIN := $(BIN_DIR)/pascal1981-proxy
PRETTY81_BIN := $(BIN_DIR)/pretty81
RUNTIME_LIB := runtime/build/libpascalrt.a
RUNTIME_SRCS := $(wildcard runtime/*.c runtime/*.h) runtime/Makefile
# pasboot translates the gen1 sources to C; no other Pascal compiler is needed
# to bootstrap. prelude.h is included by the C it writes, so it counts too.
PASBOOT := bootstrap/build/pasboot
PASBOOT_SRCS := $(wildcard bootstrap/*.c bootstrap/*.h) bootstrap/Makefile
STAGES := lexer parser typechecker codegen
# Every stage splices jsonutil.inc, so a change to the interface must rebuild
# all of them -- $INCLUDE is textual, and make cannot see through it.
STAGE_SRCS := src/jsonutil.pas src/jsonutil.inc scripts/build-stage.sh scripts/temp-env.sh
# codegen is a composition root over these units: it splices every one of
# their .inc interfaces and links every .pas as a component object. Listed
# lowest layer first -- the same order scripts/build-stage.sh compiles and
# links them in. Attached to the codegen targets alone, below, rather than to
# every stage.
CODEGEN_UNITS := argparse features cg_base cg_util cg_types cg_symbols cg_expr_shape cg_expr_sets cg_expr_support cg_expr_literals cg_expr_vector cg_expr cg_io cg_stmt cg_decl
CODEGEN_SRCS := $(foreach u,$(CODEGEN_UNITS),src/$(u).pas src/$(u).inc) src/cg_initck_proof.inc
# typechecker follows the same separately-compiled unit pattern as codegen.
# Its list is also lowest layer first and must match scripts/build-stage.sh.
TYPECHECKER_UNITS := argparse features tc_base tc_types tc_expr tc_stmt tc_decl
TYPECHECKER_SRCS := $(foreach u,$(TYPECHECKER_UNITS),src/$(u).pas src/$(u).inc)
# parser follows the same separately-compiled unit pattern. Its list is
# lowest layer first and must match scripts/build-stage.sh. ps_expr also owns
# type parsing: SIZEOF(type) reaches types from factors while ADS(space) reaches
# expressions from types, so the 1981 unit DAG cannot split that SCC further.
PARSER_UNITS := argparse ps_base ps_expr ps_stmt ps_decl
PARSER_SRCS := $(foreach u,$(PARSER_UNITS),src/$(u).pas src/$(u).inc)
GEN1_BINS := $(addprefix $(BUILD_DIR)/gen1/,$(STAGES))
GEN2_BINS := $(addprefix $(BUILD_DIR)/gen2/,$(STAGES))
GEN3_BINS := $(addprefix $(BUILD_DIR)/gen3/,$(STAGES))
GEN4_BINS := $(addprefix $(BUILD_DIR)/gen4/,$(STAGES))
BOOTSTRAP_BINS := $(addprefix $(BIN_DIR)/,$(STAGES))
FIXED_POINT := $(BUILD_DIR)/.fixed-point-verified

.PHONY: all runtime driver bootstrap beautify clean cleaner cleanest tidy test-gpu test-elisp test-bootstrap

all: runtime driver bootstrap $(PROXY_BIN) $(PRETTY81_BIN)

runtime: $(RUNTIME_LIB)

$(RUNTIME_LIB): $(RUNTIME_SRCS)
	$(MAKE) -C runtime

$(PASBOOT): $(PASBOOT_SRCS)
	$(MAKE) -C bootstrap

driver: $(DRIVER_BIN)

$(DRIVER_BIN): src/driver.pas src/argparse.pas src/argparse.inc $(STAGE_SRCS) $(GEN4_BINS) $(BOOTSTRAP_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@
	ln -sf pascal1981-native $(DRIVER_ALIAS)

$(ASTCOMPARE_BIN): src/astcompare.pas $(STAGE_SRCS) $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@

# The completion proxy. Like astcompare, a standalone program built by the
# gen4 fixed point rather than a bootstrap stage, so it is free to use units
# the reference compiler has never seen.
$(PROXY_BIN): src/proxy.pas src/bytebuf.pas src/bytebuf.inc src/argparse.pas src/argparse.inc src/jsonx.pas src/jsonx.inc src/netsock.pas src/netsock.inc src/httpio.pas src/httpio.inc src/proxycore.pas src/proxycore.inc $(STAGE_SRCS) $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@

# pretty81: a Pascal formatter, standing outside the self-hosting core the
# same way astcompare/proxy do -- built once by the gen4 fixed point rather
# than a bootstrap stage. It reads the typechecked JSON AST and emits
# formatted Pascal source; wired into the driver as `--pretty-print`.
$(PRETTY81_BIN): src/pretty81.pas $(STAGE_SRCS) $(GEN4_BINS) $(FIXED_POINT) $(RUNTIME_LIB) | $(BIN_DIR)
	NATIVE_LEXER="$(abspath $(BUILD_DIR)/gen4/lexer)" NATIVE_PARSER="$(abspath $(BUILD_DIR)/gen4/parser)" NATIVE_TYPECHECKER="$(abspath $(BUILD_DIR)/gen4/typechecker)" NATIVE_CODEGEN="$(abspath $(BUILD_DIR)/gen4/codegen)" ./scripts/build-stage.sh $< $@

# Linux-only test launcher builds this on demand, independently of bootstrap.
# Separate launchers may build concurrently: publish only a complete .so and
# never truncate one that another process has already mapped.
$(BUILD_DIR)/test-no-core.so: tests/lib/no_core.c | $(BUILD_DIR)
	@tmp=$$(mktemp "$@.XXXXXX"); \
	trap 'rm -f "$$tmp"' EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; \
	$(CC) -shared -fPIC $(CFLAGS) $< -o "$$tmp" && \
	mv -f "$$tmp" "$@"

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

bootstrap: $(BOOTSTRAP_BINS)

$(BUILD_DIR)/gen1/%: src/%.pas $(STAGE_SRCS) $(RUNTIME_LIB) $(PASBOOT) $(PASBOOT_SRCS) | $(BUILD_DIR)/gen1
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
# Name every generation's stages as targets. GNU make 4.3 otherwise treats a
# stage reached only through the pattern rules (each lexer) as intermediate
# and deletes it after the build; mathck_bootstrap_audit runs them.
$(GEN1_BINS) $(GEN2_BINS) $(GEN3_BINS) $(GEN4_BINS):

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
	rm -rf bin/lexer bin/parser bin/typechecker bin/codegen bin/astcompare bin/pascal1981-proxy bin/pascal1981-native bin/pascal1981 bin/pretty81
	$(MAKE) -C runtime cleaner
	$(MAKE) -C bootstrap cleaner

cleanest: cleaner
	rm -rf .pytest_cache

# Tests. A suite is an executable file in a tier directory, tests/<tier>/,
# and tests/lib/schedule.sh runs suites in parallel, longest first, and
# reports on them (see tests/README.md). Make only builds what they test.
#   check     static checks of the sources and repository tooling
#   unit      runtime C units, pasboot fixtures, the test launcher
#   corpus    fixture corpora compiled and compared with expected output
#   contract  scripted checks of compiler, driver and runtime behavior
#   service   the completion proxy against a stub backend
#   optional  opt-in: needs hardware or measures, never run by `make test`
# The check and unit tiers need no bootstrap, so `make test` runs them
# first, while nothing is built yet, then builds every tool with BUILD_JOBS
# parallel jobs and runs the other tiers. It runs every suite even after
# one fails, and ends with a summary of failures and skips; each suite's
# output is kept in build/test-results/. To run some suites, name tiers or
# suites: make test SUITES="mathck_vector depth", or run the suite itself.
# TEST_JOBS processes, by default every CPU, are shared by the suites
# running and the work inside each; see tests/lib/schedule.sh.
SCHEDULE := ./tests/lib/schedule.sh $(if $(TEST_JOBS),-j $(TEST_JOBS))
QUICK_TIERS := check unit
QUICK_TOOLS := runtime $(PASBOOT) $(BUILD_DIR)/test-no-core.so
TEST_TOOLS := $(QUICK_TOOLS) bootstrap $(DRIVER_BIN) $(ASTCOMPARE_BIN) $(PROXY_BIN) $(PRETTY81_BIN)

.PHONY: test test-quick test-tools print-gen1-compilands
ifdef SUITES
test: $(TEST_TOOLS)
	@$(SCHEDULE) $(SUITES)
else
test: $(QUICK_TOOLS)
	@rm -rf $(BUILD_DIR)/test-results
	-@$(SCHEDULE) $(QUICK_TIERS)
	@$(MAKE) --no-print-directory -j$(BUILD_JOBS) test-tools || { $(SCHEDULE) --summary; exit 1; }
	-@$(SCHEDULE) corpus contract service
	@$(SCHEDULE) --summary
endif

# Seconds, and no bootstrap: suitable before every commit.
test-quick: $(QUICK_TOOLS)
	@$(SCHEDULE) $(QUICK_TIERS)

test-tools: $(TEST_TOOLS)

# Every gen1 compiland, for tests/check/bootstrap_subset.sh: the gen1 stages
# and their units.
GEN1_COMPILANDS := $(sort jsonutil $(CODEGEN_UNITS) $(TYPECHECKER_UNITS) $(PARSER_UNITS) $(STAGES))
print-gen1-compilands:
	@echo $(GEN1_COMPILANDS)

# Run the real-GPU CUDA integration test. The runner exits successfully with a
# clear skip reason when its hardware or toolchain prerequisites are absent.
test-gpu: bootstrap
	@$(SCHEDULE) -v gpu_orchestration

# Run the Emacs major-mode ERT suite. Kept separate from `test` because Emacs
# is not a dependency of the compiler toolchain.
test-elisp: bootstrap $(PRETTY81_BIN) $(DRIVER_BIN)
	$(TEST_ENV) $(MAKE) -C elisp test

# Full fixed-point regression: force a clean gen1->gen4 rebuild (not reusing
# any cached generation) and fail if gen3/gen4 aren't byte-identical. Separate
# from `test` because it's the slowest thing in the repo. pascal1981, python
# and python3 are shadowed on PATH by stubs that fail, so the bootstrap is
# proven to need no Python even on a machine that has it.
NO_PYTHON_DIR := $(BUILD_DIR)/no-python
# This target deletes artifacts other goals may be using, especially with -j.
ifneq ($(filter test-bootstrap,$(MAKECMDGOALS)),)
ifneq ($(words $(MAKECMDGOALS)),1)
$(error test-bootstrap deletes build/: run it separately from other goals)
endif
endif

test-bootstrap:
	rm -rf $(BUILD_DIR)
	mkdir -p $(NO_PYTHON_DIR)
	for tool in pascal1981 python python3; do \
	  printf '#!/bin/sh\necho "test-bootstrap: $$0 was invoked; the bootstrap must not need Python" >&2\nexit 1\n' > $(NO_PYTHON_DIR)/$$tool; \
	  chmod +x $(NO_PYTHON_DIR)/$$tool; \
	done
	PATH="$(abspath $(NO_PYTHON_DIR)):$$PATH" USE_PYTHON_REFERENCE=0 $(MAKE) bootstrap
