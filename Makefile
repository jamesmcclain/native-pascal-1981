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

# make -j parallelizes targets, not the fixture loop inside tests/run.sh.
# Keep the default bounded; override independently, e.g. TEST_JOBS=8.
TEST_JOBS ?= 8
# Parallel jobs for test-native's tool build.
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

.PHONY: all runtime driver bootstrap beautify clean cleaner cleanest tidy test test-driver test-native test-descriptor-contract test-super-new test-parser-named-index test-typecheck-named-index test-sysutil test-proxy test-gpu test-reference-parity test-elisp test-bootstrap test-pasboot check-bootstrap-subset

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
$(BUILD_DIR)/test-no-core.so: tests/support/no_core.c | $(BUILD_DIR)
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

test: check-bootstrap-subset test-pasboot test-native test-proxy
	$(TEST_ENV) ./tests/test_precommit_hook.sh

# Every gen1 compiland must stay inside the subset pasboot translates
# (docs/bootstrap_subset.md). Parse-only, so a src/ change that leaves the
# subset fails here, in seconds, naming the construct and line, rather than
# deep inside a gen1 build. The list is the gen1 stages and their units.
GEN1_COMPILANDS := $(sort jsonutil $(CODEGEN_UNITS) $(TYPECHECKER_UNITS) $(PARSER_UNITS) $(STAGES))
check-bootstrap-subset: $(PASBOOT)
	@for u in $(GEN1_COMPILANDS); do \
	  $(PASBOOT) --parse-only src/$$u.pas || exit 1; \
	done
	@echo "check-bootstrap-subset: $(words $(GEN1_COMPILANDS)) gen1 compilands are inside the bootstrap subset"

# pasboot's per-feature fixtures (bootstrap/tests/). Needs only clang, libc
# and the runtime library -- no Pascal compiler.
test-pasboot: $(PASBOOT) $(RUNTIME_LIB)
	$(TEST_ENV) ./bootstrap/tests/run.sh

# The zero-Python subset of `test`: driver, golden-file behavioral, and
# IR/PTX-text directive tests. It does not run pytest or Python.
test-driver: $(DRIVER_BIN)
	$(TEST_ENV) ./tests/driver.sh

# Whole host descriptor transport and explicit unsafe-boundary contracts.
# Install current stages as well: the driver dispatches through bin/.
test-descriptor-contract: $(DRIVER_BIN) bootstrap
	$(TEST_ENV) ./tests/descriptor_contract.sh

test-parser-named-index: $(PRETTY81_BIN)
	$(TEST_ENV) ./tests/array_named_index_parser.sh

test-typecheck-named-index: $(BIN_DIR)/typechecker $(BIN_DIR)/parser $(BIN_DIR)/lexer
	$(TEST_ENV) ./tests/array_named_index_typecheck.sh

test-super-new: $(DRIVER_BIN) bootstrap
	$(TEST_ENV) bash tests/super_new_contract.sh

# Every tool test-native runs, so they can be built ahead of the tests.
NATIVE_TEST_TOOLS := runtime bootstrap $(DRIVER_BIN) $(ASTCOMPARE_BIN) $(PROXY_BIN) $(PRETTY81_BIN) $(BUILD_DIR)/test-no-core.so

# test-native suites run as ./tests/NAME.sh, longest first (measured warm,
# 2026-10-04), with the many-worker suites interleaved among the single-core
# ones so that TEST_SUITE_JOBS slots keep the machine busy without piling
# every worker pool up at once. Each runs in its own scratch workspace.
# (Lower priority for the many-worker suites, or more slots, measured slower.)
NATIVE_SUITES := mathck_mixed_width initck_heap mathck_twins initck_aggregates \
  mathck_scalar initck_validation initck_external mathck_builtins \
  initck_definite mathck_bootstrap_audit initck_routines mathck_vector \
  initck_scalar mathck_for_endpoints mathck_word_scalar initck_abi \
  mathck_divmod_safety initck_producers mathck_baseline trunc_round_range \
  initck_contract checklit mathck_metadata mathck_constant_folding depth \
  mathck_device stage_cli indexck_metadata mathck_boundary_values \
  mathck_diagnostics mathck_address_arith mathck_optimization initck_state \
  mathck_overflow astcompare indexck_guard_ir codegen_set_base_guard \
  set_enum_typecheck
NATIVE_SUITE_TARGETS := $(addprefix native-suite-,$(NATIVE_SUITES))

# Build every tool with BUILD_JOBS parallel jobs (the runtime objects,
# pasboot, and the four stages within each bootstrap generation build
# concurrently; generations still build in order), then run every suite with
# up to TEST_SUITE_JOBS at once. --output-sync keeps each suite's output
# together. TEST_SUITE_JOBS=1 runs the suites one at a time, in the order
# below; as with any make -j, a failure stops new suites from starting.
TEST_SUITE_JOBS ?= 6
test-native:
	$(MAKE) -j$(BUILD_JOBS) $(NATIVE_TEST_TOOLS)
	$(MAKE) -j$(TEST_SUITE_JOBS) --output-sync=target native-suites

.PHONY: native-suites native-golden native-read-wide native-no-core native-temp-hygiene $(NATIVE_SUITE_TARGETS)
native-suites: native-golden $(word 1,$(NATIVE_SUITE_TARGETS)) $(word 2,$(NATIVE_SUITE_TARGETS)) \
  $(word 3,$(NATIVE_SUITE_TARGETS)) test-descriptor-contract test-sysutil test-driver test-parser-named-index \
  test-typecheck-named-index test-super-new native-read-wide \
  $(NATIVE_SUITE_TARGETS) native-no-core native-temp-hygiene

native-golden: $(DRIVER_BIN) bootstrap
	$(TEST_ENV) ./tests/run.sh -j $(TEST_JOBS)

native-read-wide: $(RUNTIME_LIB)
	$(CC) -o $(BUILD_DIR)/read_wide_runtime tests/read_wide_runtime.c $(RUNTIME_LIB)
	$(TEST_ENV) $(BUILD_DIR)/read_wide_runtime

native-no-core: $(BUILD_DIR)/test-no-core.so
	$(TEST_ENV) ./tests/test_no_core.py

native-temp-hygiene: $(DRIVER_BIN)
	$(TEST_ENV) python3 tests/temp_hygiene.py

$(NATIVE_SUITE_TARGETS): native-suite-%: $(DRIVER_BIN) $(ASTCOMPARE_BIN) bootstrap
	$(TEST_ENV) ./tests/$*.sh

# Reusable POSIX filesystem and process primitives, exercised from Pascal.
test-sysutil: $(DRIVER_BIN) runtime
	$(TEST_ENV) ./tests/sysutil_check.sh $(DRIVER_ALIAS)

# Completion-proxy conformance against recorded golden reports, plus native
# transforms/client/corpus checks. The replaced Python proxy is not run.
# Retain Python orchestration and the deterministic stub outside the first
# harness migration; this is not part of test-driver's zero-Python subset.
test-proxy: $(PROXY_BIN) $(DRIVER_BIN)
	$(TEST_ENV) ./tests/proxy/run.sh $(PROXY_BIN)
	$(TEST_ENV) ./tests/proxy/transforms_check.sh $(DRIVER_ALIAS)
	$(TEST_ENV) ./tests/proxy/oneshot.sh
	$(TEST_ENV) ./tests/proxy/corpus_reference_check.sh $(DRIVER_ALIAS)
	$(TEST_ENV) ./tests/proxy/corpus_smoke.sh

# Run the real-GPU CUDA integration test. The runner exits successfully with a
# clear skip reason when its hardware or toolchain prerequisites are absent.
test-gpu: bootstrap
	$(TEST_ENV) ./tests/gpu_orchestration.sh

# Compare the native compiler stages with the earlier Python implementation.
# Disabled by default: the native compiler is authoritative and deliberately
# diverges (e.g. INITCK read-site metadata), so the suite is kept only for
# occasional manual comparison. Removal needs a separate scope decision. Set
# ENABLE_PYTHON_PARITY=1 to run it; Python is never needed by the build.
PYTHON ?= python3
test-reference-parity:
ifeq ($(ENABLE_PYTHON_PARITY),1)
	$(TEST_ENV) env PYTHONPATH=. $(PYTHON) -m pytest tests/parity/
else
	@echo 'test-reference-parity: disabled (not authoritative; ENABLE_PYTHON_PARITY=1 to run)'
endif

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
