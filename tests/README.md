# Test Suites for `native-pascal-1981`

This directory contains the automated test suites for the native Pascal 1981 compiler toolchain.

## Contents

- [How the tests are organized](#how-the-tests-are-organized)
- [Suite index](#suite-index)
- [Environment and concurrency](#environment-and-concurrency)
- [Suite details](#suite-details)
- [Topic notes](#topic-notes)

Longer accounts live in their own documents:

- [MATHCK tests](../docs/testing/mathck.md): the test map and the G1–G29 gap baseline
- [INITCK tests](../docs/testing/initck.md): the support boundary and its suites
- [Host descriptor contract tests](../docs/testing/descriptors.md)
- [Opt-in overhead measurements](../docs/testing/overhead.md)
- [Retained Python test infrastructure](../docs/testing/retained_python.md): what is kept and why
- [Temporary-file ownership](../docs/temporary_files.md) and [test portability](../docs/test_portability.md): rules every suite follows

## How the tests are organized

A **suite** is a `*.sh` or `*.py` file directly inside a **tier** directory;
the tier's subdirectories hold its data. The tiers group suites by what they
do mechanically:

| Tier | Suites |
| --- | --- |
| `check/` | static checks: `bootstrap_subset` (gen1 stays inside the pasboot subset), `precommit_hook` (the hook and `beautify.sh`), `suite_index` (the index below is current) |
| `unit/` | `runtime` (C unit programs `runtime_*.c` against the runtime library), `pasboot` (translator fixtures in `unit/pasboot/`), `no_core` (the test launcher) |
| `corpus/` | fixture corpora compiled and compared with expected output: `fixtures` (run and check fixtures in `corpus/golden/`, `corpus/integration/`, `corpus/dialect/`, `corpus/checklit/`; `corpus/sources/` holds programs that `.check` fixtures compile), `depth`, `astcompare` (`corpus/reference/`) |
| `contract/` | scripted behavioral checks: driver and stage CLIs, MATHCK/INITCK/INDEXCK/RANGECK, descriptors, sysutil, temporary-file hygiene; data in `contract/fixtures/` and `contract/descriptor/` |
| `service/` | the completion proxy, with its data in `service/proxy/` |
| `optional/` | opt-in, never in `make test`: `gpu_orchestration` (`make test-gpu`, data in `optional/gpu/`), overhead measurements |

**Where a new test goes.** A single program whose expected result is its
output, its exit status, a diagnostic, or literal substrings of its IR is a
fixture in `corpus/`, checked by `corpus/fixtures.sh` with no script of its
own (see [the fixture corpus](#fixture-corpus-testscorpusgoldenintegrationdialectchecklit)).
Write a suite script only when the check needs logic: regular expressions
or relations between outputs, generated programs, several tools, or a
process to manage. Put it in the tier that matches what it does, starting
with `source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"`.

`lib/` holds the machinery shared by every suite:

- `lib/harness.sh` is the first thing every shell suite sources. It re-runs
  the suite under `scripts/test-env.sh` when it was started by hand, puts it
  under `scripts/temp-env.sh`'s temporary-workspace supervisor, sets strict
  mode, changes to the repository root, and defines `$ROOT`, `$work` (a
  scratch directory) and `$HARNESS_JOBS`. It also supplies the shared
  helpers: `require` (a tool must be built), `pass`/`fail`/`skip`/`finish`
  (keep-going checks with a tally), `die` (stop at the first failure),
  `spawn` (bounded background work) and `unit`/`count`/`units_wait`
  (parallel units with exact cell counts).
- `lib/schedule.sh` runs suites: `tests/lib/schedule.sh [-j N] [-v] TIER|SUITE...`.

**The suite contract.** A suite passes when it exits 0. It prints a line
starting `FAIL: ` for each failure and `SKIP: ` for each check it could not
run; the scheduler's summary collects them. A suite never builds what it
tests (`make test` does), and runs the same way from `make test`, from the
scheduler, or by hand from any directory:

```sh
make test                          # every routine tier, with a summary
make test-quick                    # check and unit tiers: seconds, no bootstrap
make test SUITES="contract depth"  # some tiers or suites
./tests/contract/mathck_vector.sh  # one suite, directly
```

`make test` clears `build/test-results/`, runs the `check` and `unit` tiers,
builds every tool, runs the `corpus`, `contract` and `service` tiers, and
ends with a summary. Each suite's output is in
`build/test-results/<suite>.log`; `build/test-times` keeps each suite's
latest duration, which orders the next run longest first.

## Suite index

Generated from each suite's header by `tests/lib/index.sh --update`; the
`suite_index` check fails when it is stale. A suite's first header sentence
is its entry here.

<!-- suite-index:begin (tests/lib/index.sh --update) -->
| Tier | Suite | What it checks |
| --- | --- | --- |
| check | [`bootstrap_subset`](check/bootstrap_subset.sh) | Every gen1 compiland stays inside the subset pasboot translates. |
| check | [`precommit_hook`](check/precommit_hook.sh) | Tests for the tracked pre-commit hook and beautify.sh. |
| check | [`suite_index`](check/suite_index.sh) | The suite index in tests/README.md matches the suites and their headers. |
| unit | [`no_core`](unit/no_core.py) | Bounded checks for the test-only crash-reporter suppression launcher. |
| unit | [`pasboot`](unit/pasboot.sh) | Per-feature fixtures for pasboot, the C bootstrap translator. |
| unit | [`runtime`](unit/runtime.sh) | C unit tests of the runtime library. |
| corpus | [`astcompare`](corpus/astcompare.sh) | astcompare, the JSON AST comparator, and the frozen reference ASTs it checks. |
| corpus | [`depth`](corpus/depth.sh) | Native parser depth and resource-limit tests. |
| corpus | [`fixtures`](corpus/fixtures.sh) | Every run and check fixture in the corpus, each against what it declares. |
| contract | [`array_named_index_parser`](contract/array_named_index_parser.sh) | Named ordinal array index types parse, and pretty81 round-trips them. |
| contract | [`chr_constant_folding`](contract/chr_constant_folding.sh) | Unchecked CHR folding has the same low-eight-bit value as runtime conversion. |
| contract | [`descriptor_contract`](contract/descriptor_contract.sh) | Host descriptor transport ABI and unsupported-boundary contracts. |
| contract | [`driver_math`](contract/driver_math.sh) | The driver links REAL math builtins at every optimization level without user -lm. |
| contract | [`driver`](contract/driver.sh) | The driver: option parsing, stage dispatch, outputs and failure cleanup. |
| contract | [`indexck_diagnostics`](contract/indexck_diagnostics.sh) | INDEXCK failures report the first index token, preserving bounds and side effects. |
| contract | [`indexck_guard_ir`](contract/indexck_guard_ir.sh) | INDEXCK guard IR: only enabled host selectors are guarded, at full ordinal width. |
| contract | [`indexck_metadata`](contract/indexck_metadata.sh) | Verify native per-index metadata without Python or unchecked bad accesses. |
| contract | [`initck_abi`](contract/initck_abi.sh) | INITCK on/off twins agree on output, Pascal ABI and descriptor layout. |
| contract | [`initck_aggregates`](contract/initck_aggregates.sh) | INITCK for fixed ARRAYs and RECORDs of scalar leaves. |
| contract | [`initck_contract`](contract/initck_contract.sh) | INITCK metadata, legacy opt-out and boundary diagnostics; bad reads compile-only. |
| contract | [`initck_definite`](contract/initck_definite.sh) | Compile-time proofs at O0, plus success/failure parity at every driver level. |
| contract | [`initck_external`](contract/initck_external.sh) | INITCK at external boundaries: C code that reads or writes Pascal storage. |
| contract | [`initck_heap`](contract/initck_heap.sh) | INITCK for pointers and heap storage. |
| contract | [`initck_producers`](contract/initck_producers.sh) | INITCK scalar producers beyond literal assignment. |
| contract | [`initck_routines`](contract/initck_routines.sh) | INITCK at routine boundaries: parameters, results and defaults. |
| contract | [`initck_scalar`](contract/initck_scalar.sh) | INITCK producers and guards for scalar locals. |
| contract | [`initck_state`](contract/initck_state.sh) | Shadow allocation/reset independently of enabled guards (see initck_scalar.sh). |
| contract | [`initck_validation`](contract/initck_validation.sh) | INITCK release gate: checked success and failure, values, ABI. |
| contract | [`mathck_address_arith`](contract/mathck_address_arith.sh) | Address arithmetic and [C] values at MATHCK's boundary. |
| contract | [`mathck_baseline`](contract/mathck_baseline.sh) | Executable G1-G29 gap inventory, not a claim that MATHCK is implemented. |
| contract | [`mathck_bootstrap_audit`](contract/mathck_bootstrap_audit.sh) | The arithmetic the self-hosting compiler sources depend on. |
| contract | [`mathck_boundary_values`](contract/mathck_boundary_values.sh) | Legitimate boundary values never trap under MATHCK+. |
| contract | [`mathck_builtins`](contract/mathck_builtins.sh) | MATHCK and RANGECK on SUCC/PRED/ABS/SQR, and the SADDOK family. |
| contract | [`mathck_constant_folding`](contract/mathck_constant_folding.sh) | Constant DIV/MOD folding, consumer adaptation and zero rejection. |
| contract | [`mathck_device`](contract/mathck_device.sh) | MATHCK in DEVICE code, on NVPTX and on the CPU. |
| contract | [`mathck_diagnostics`](contract/mathck_diagnostics.sh) | MATHCK diagnostics are located and distinct from the other checks'. |
| contract | [`mathck_divmod_safety`](contract/mathck_divmod_safety.sh) | Scalar DIV/MOD safety: zero divisors and MIN DIV -1 at every width. |
| contract | [`mathck_for_endpoints`](contract/mathck_for_endpoints.sh) | FOR loops terminate at the final value without stepping past it (G18, G19). |
| contract | [`mathck_metadata`](contract/mathck_metadata.sh) | Verify per-operation MATHCK snapshots survive parser/typechecker/codegen. |
| contract | [`mathck_mixed_width`](contract/mathck_mixed_width.sh) | MATHCK for operands of different integer widths, and G24 admission. |
| contract | [`mathck_optimization`](contract/mathck_optimization.sh) | MATHCK optimization never weakens the runtime contract. |
| contract | [`mathck_overflow`](contract/mathck_overflow.sh) | MATHCK O0 guard order: each check precedes its operation. |
| contract | [`mathck_scalar`](contract/mathck_scalar.sh) | MATHCK on scalar arithmetic at every integer width. |
| contract | [`mathck_twins`](contract/mathck_twins.sh) | Programs that never overflow behave identically under MATHCK+ and MATHCK-. |
| contract | [`mathck_vector`](contract/mathck_vector.sh) | MATHCK on integer VECTOR lanes and the VSUM/VPROD reductions. |
| contract | [`mathck_word_scalar`](contract/mathck_word_scalar.sh) | Scalar WORD arithmetic against native arithmetic oracles. |
| contract | [`pretty81_integers`](contract/pretty81_integers.sh) | pretty81 preserves exact signed INTEGER64 literals through parsed and typed ASTs. |
| contract | [`pretty81_sequential`](contract/pretty81_sequential.sh) | pretty81 prints AND THEN/OR ELSE chains without parentheses, which the 1981 manual forbids around them: its output parses again, prints the same text, and the program behaves the same. |
| contract | [`quoted_literal_limits`](contract/quoted_literal_limits.sh) | Quoted token spellings include both delimiters and doubled quotes. |
| contract | [`rangeck_case`](contract/rangeck_case.sh) | RANGECK CASE misses fail once, preserving snapshots, OTHERWISE and target boundaries. |
| contract | [`rangeck_chr`](contract/rangeck_chr.sh) | CHR checks original integer values at its name token, before narrowing. |
| contract | [`rangeck_concat`](contract/rangeck_concat.sh) | CONCAT checks the wide combined length before copying or publishing it. |
| contract | [`rangeck_scope`](contract/rangeck_scope.sh) | RANGECK settings reach the AST and IR of FOR, CASE and SUCC where they apply. |
| contract | [`stage_cli`](contract/stage_cli.sh) | Standalone compiler-stage command-line contract tests. |
| contract | [`super_new_contract`](contract/super_new_contract.sh) | Hardened NEW failures, inspected through a test-only C harness. |
| contract | [`sysutil`](contract/sysutil.sh) | Exercise the reusable filesystem and child-process substrate from Pascal. |
| contract | [`temp_hygiene`](contract/temp_hygiene.py) | Temporary ownership, exit/signal cleanup, and parallel fixture regressions. |
| contract | [`trunc_round_range`](contract/trunc_round_range.sh) | TRUNC/ROUND INTEGER range check (G26): always on, independent of MATHCK. |
| service | [`proxy_conformance`](service/proxy_conformance.sh) | Check a proxy implementation against the recorded conformance golden. |
| service | [`proxy_corpus_reference`](service/proxy_corpus_reference.sh) | Compile recorded reference continuations with the native compiler. |
| service | [`proxy_corpus_smoke`](service/proxy_corpus_smoke.sh) | Replay the realistic completion corpus using the native Pascal client. |
| service | [`proxy_oneshot`](service/proxy_oneshot.sh) | Check tests/service/proxy/oneshot.pas -- one upstream call, in Pascal -- against the deterministic stub backend. |
| service | [`proxy_transforms`](service/proxy_transforms.sh) | Check proxycore's pure transforms against the frozen native golden corpus. |
| optional | [`gpu_orchestration`](optional/gpu_orchestration.sh) | Compile and run vector addition through the real CUDA device backend. |
| optional | [`initck_overhead`](optional/initck_overhead.py) | Opt-in INITCK measurement, not a timing pass/fail gate. |
| optional | [`mathck_overhead`](optional/mathck_overhead.py) | Opt-in MATHCK measurement, not a timing pass/fail gate. |
<!-- suite-index:end -->

## Environment and concurrency

`make test` first builds every tool it needs with `BUILD_JOBS`
(default 8) parallel jobs: the runtime objects, pasboot and the four stages
within each bootstrap generation build concurrently, while generations still
build in order. A full rebuild takes about 205 s this way, against about
310 s serially. `tests/lib/schedule.sh` then runs the suites, longest first
by their previous durations, within one budget of `TEST_JOBS` processes
(default: every CPU) shared by the suites running and the work inside each.
A suite costs 1 unless it contains the line `# schedule: parallel`, which
marks a suite that fans out (the golden runner, and the MATHCK suites built
on the harness's `unit`/`spawn`); such a suite costs `TEST_PARALLEL_JOBS`
(default half the budget) and is given that number as `PASCAL_TEST_JOBS`,
which the harness exposes as `$HARNESS_JOBS` and `spawn`/`unit` respect.
Every waiting suite whose cost fits what is left starts. Use `TEST_JOBS=1`
to run suites one at a time when debugging; a suite run by hand uses every
CPU unless `PASCAL_TEST_JOBS` says otherwise.

Suites are launched through `scripts/test-env.sh`. On Linux,
this preloads a small **test-only** constructor that sets `PR_SET_DUMPABLE=0`
after each dynamic `exec`, including descendants. A zero core-size limit
alone does not stop piped core handlers such as Ubuntu Apport: each expected
abort can otherwise spend about a second reporting a crash. The launcher
preserves exit signals, stdout and stderr; production runtime code is untouched.
Other platforms only use a zero core-size limit. Static/set-ID executables
cannot rely on this preload mechanism.

Use the same environment for standalone focused tests:

```sh
./tests/contract/mathck_divmod_safety.sh
./tests/contract/mathck_constant_folding.sh
```

Set `PASCAL_TEST_CORES=1` to opt out for crash debugging (subject to your
shell/system core limits). The Linux shim is built/cached independently at
`build/test-no-core.so`; this never requires a compiler bootstrap. Existing
`LD_PRELOAD` entries are preserved. No system-wide crash-report setting changes.

### Host compiler warnings

`scripts/test-env.sh` also sets `PASCAL1981_CC` to `scripts/test-cc.sh`,
which runs the real compiler (`PASCAL1981_TEST_CC`, defaulting to the
caller's `PASCAL1981_CC`, then `CC`, then `clang`). Compilers print
harmless text that varies by version and host, so the wrapper drops clang's
warning lines: `clang: warning: ...` from its driver, warnings tagged
`[-W...]`, and `N warnings generated.`. Suites that require an empty
compiler stderr then check only what the Pascal stages print. Errors and
the exit status pass through unchanged. A suite
that sets `PASCAL1981_CC` itself (`tests/contract/driver.sh`'s fake clang) bypasses
the wrapper. The C helper programs that suites build directly use the
Makefile's `-Wall -Wextra` without `-Werror`, so a new compiler's new
warning is reported without failing the suite. See
[test portability](../docs/test_portability.md) for the rules behind this.

During iteration, build tools incrementally and run affected fixtures/scripts.
Reserve the full bootstrap/native suite for the final integration gate, after
formatting; do not repeat a clean release gate merely because a commit hook
ran. Runtime archive changes can invalidate every bootstrap generation.

`test-bootstrap` is intentionally different: it deletes `build/` and rebuilds
all compiler generations, so it must run separately. Make rejects combining
it with other goals to prevent deletion/build races. It does not use the
preload launcher (which itself lives in `build/`), and has no expected-abort
runtime fixtures. Its compilation cost is real; more test workers cannot
remove generation dependency barriers.

Crash-report suppression matters for cost: on the development host with warm
native tools, the main 331-fixture runner at eight workers takes about 12
seconds with suppression versus about 56 without it, and the DIV/MOD suite's
160 expected aborts would otherwise cost minutes of crash reporting. A clean
`make -j8 test-bootstrap` takes a few minutes of mostly compilation time.
These are observed host timings, not timing-sensitive correctness oracles.

## Suite details

### Driver contract (`tests/contract/driver.sh`)
- **Runner**: [`tests/contract/driver.sh`](contract/driver.sh)
- **Description**: Checks the public driver CLI without a bootstrap build. The runner uses temporary stage programs to check option errors, missing sources and stages, failed stages and `clang`, literal source and output paths, default IR output, and multi-file linking.
- **Running**:
  ```bash
  ./tests/contract/driver.sh
  ```

### Fixture corpus (`tests/corpus/{golden,integration,dialect,checklit}/`)
- **Runner**: [`tests/corpus/fixtures.sh`](corpus/fixtures.sh); its header is the
  reference for the fixture format.
- **Description**: one runner, one directive language. A fixture without
  CHECK directives is compiled with the native driver, run, and compared
  with its sidecar files (`.out`, `.err`, `.exitcode`, `.stdin`, `.args`,
  `.build.sh`). A fixture with CHECK directives (all of `checklit/`) is
  compiled to LLVM IR or PTX text, or piped through the stages that
  `CHECK-STAGES` names, and checked with literal, unordered substring
  directives (`CHECK`, `CHECK-NOT`, `CHECK-ANY`, `CHECK-COUNT`,
  `CHECK-FAIL`). Either kind may ask for a compile matrix with
  `{ DIALECT: vintage extended }` and `{ OPT: 0 1 2 3 }`; each cell is a
  separate check. Directives are parsed by `tests/lib/fixture.sh`, which
  `mathck_twins` shares.
- **Running**:
  ```bash
  ./tests/corpus/fixtures.sh                     # every fixture
  ./tests/corpus/fixtures.sh -v tests/corpus/golden/01_hello.pas
  ```

### Completion-proxy conformance (retained)

Keep proxy conformance outside the first Python-harness migration. `make test`
runs it as the `service` tier; run it alone with `make test SUITES=service`,
or one wrapper as `./tests/service/proxy_<name>.sh`. The canonical
[proxy suite guide](service/proxy/README.md) describes its fixtures and normalization
contract. Frozen reports came from the replaced Python **proxy**, not the
Python **compiler**; the old proxy implementation is no longer run.

| Retained Python component | Purpose / invocation | Maintenance responsibility |
| --- | --- | --- |
| `service/proxy/run_conformance.py` | `tests/service/proxy_conformance.sh` calls it to orchestrate stub/proxy daemons and native raw-request replay, then calls it again with `--compare` for recorded-report equality. Calibration/response normalization remain Python. | Proxy protocol maintainers own normalization, daemon lifecycle, calibration and case membership. Preserve golden failures; `--record` is for an intentional contract change, not blessing current output. Keep native_temp for private diagnostic logs. |
| `service/proxy/stub_upstream.py` | Deterministic HTTP reply shapes and request-payload inspection; launched by conformance, `proxy_oneshot.sh`, and default `proxy_corpus_smoke.sh`. An explicit smoke `--base-url` bypasses the stub. | Proxy/client maintainers own scenario markers, malformed/error/timeout replies, effort calibration and payload capture. Retain deterministic local tests; a live model is not an equality oracle. |

The other service suites (`proxy_transforms.sh` and
`proxy_corpus_reference.sh`) are native checks.
The [proxy wrapper audit](../docs/testing/retained_python.md#proxy-wrapper-audit)
records private port-publication coverage and outstanding daemon-supervision
and case-uniqueness findings. Retention is not a claim that all paths are fully
hardened.

### Ported from the retired Python parity suite

The Python parity suite (`tests/parity/`, with `tests/support.py`) compared
the native stages with the earlier Python compiler. It was retired on
2026-10-04: agreement with that compiler is no longer a goal, and it no
longer ran anywhere. What it checked of native behavior, independent of the
Python compiler, now lives here:

- **Front-end fixtures**: the 97 parser and typechecker programs it walked
  are check fixtures in `corpus/checklit/parser/` and `corpus/checklit/typecheck/`
  (`should_pass/`, `should_fail/`). Passing ones must leave stderr empty,
  and typecheck ones go through codegen to IR that clang assembles
  (`CHECK-ASSEMBLE`); failing ones fail at the intended stage, with their
  exact diagnostics in `.err`. Of its two judgment calls, `A_write_field_width`
  is accepted and `B_colon_args_any_call` is rejected.
- **Device codegen**: the kernel attribute and launch-ABI assertions had
  already moved to `corpus/checklit/` (`device_kernel_attrs*.check`,
  `host_launch_abi.check`, `cuda_host_launch_abi.check`). The rest is now
  `corpus/golden/launch_geometry.pas` (both LAUNCH geometry forms, run),
  `corpus/integration/cpu_device_roundtrip.pas` (DEVALLOC to DEVFREE, run),
  `corpus/integration/cpu_device_uses_rename.pas` (a USES alias and the
  original name both launch the kernel) and `corpus/checklit/device_guards/`
  (NVPTX transcendental and allocation rejections, CPU libm calls, and the
  codegen guards it reached by editing ASTs, reached here from source with
  the typechecker bypassed).
- **Record layout** is no longer a test: codegen checks every record it
  lowers for the host (`CheckRecordLayout` in `src/cg_types.pas`). The byte
  offsets that field access uses and the size that SIZEOF and NEW use must
  equal LLVM's layout of the struct type it emits, or the compile stops
  with an internal error. So every record in every compile is checked,
  including all of the compiler's own each time it builds itself. NVPTX
  modules are not checked: they get their data layout only when PTX is
  emitted.

Its AST and acceptance comparisons, linked-output comparisons and
reference-compiler depth tests had no native content; the corpus's expected
outputs and `corpus/depth.sh` cover those behaviors natively.

### Frozen ASTs for check fixtures
- A `.check` file in `checklit/` uses `{ CHECK-INPUT: path.json }`: the
  runner sends that typed AST to native codegen. Sources and frozen Python
  reference ASTs are in `tests/corpus/reference/codegen/`. A frozen AST is
  produced by the Python reference, so it can never contain `VECTOR` -- use a
  plain `.pas` check fixture for any `VECTOR` IR-shape assertion.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-codegen.sh`. Review all JSON changes before you commit them. Routine tests do not run this Python-based maintenance command.

### Depth limits (`tests/corpus/depth.sh`)

- **Runner**: [`tests/corpus/depth.sh`](corpus/depth.sh)
- **Description**: Checks expression, statement, and type nesting boundaries in the native parser. It checks depth unwinding between sibling expressions. It also sends frozen oversized ASTs to the native typechecker and code generator. Bounded tests use a five-second timeout; parser and typechecker tests also use a 128 MiB address-space limit.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-depth.py`. Review changes under `tests/corpus/reference/depth/` before you commit them. Routine tests do not run this maintenance command.
- **Running**:
  ```bash
  ./tests/corpus/depth.sh
  ```

### JSON AST comparator (`tests/corpus/astcompare.sh`)

- **Runner**: [`tests/corpus/astcompare.sh`](corpus/astcompare.sh)
- **Tool**: `bin/astcompare`
- **Description**: Checks structural JSON comparison without Python. Object keys are unordered, arrays are ordered, and `--ignore-key KEY` applies recursively. Mismatches report a JSON path. The suite also compares native parser and typechecker output with frozen Python-reference ASTs. Typed comparisons ignore the output-only `resolved_type` field.
- **Artifact updates**: Run `./scripts/update-reference-ast.sh`. Review the Pascal sources and JSON under `tests/corpus/reference/ast/` before you commit changes. Routine tests do not run this Python-based maintenance command.
- **Running**:
  ```bash
  ./tests/corpus/astcompare.sh
  ```

### GPU orchestration (`tests/optional/gpu_orchestration.sh`)

- **Runner**: [`tests/optional/gpu_orchestration.sh`](optional/gpu_orchestration.sh)
- **Description**: Compiles and runs vector addition with the CUDA backend. The runner uses frozen typed ASTs from the independent Python front end. It checks each GPU and CUDA prerequisite. It prints one skip reason if a prerequisite is not available.
- **Artifact updates**: Run `./scripts/update-reference-gpu.sh`. Review the Pascal sources and typed ASTs under `tests/optional/gpu/` before you commit changes.
- **Running**:
  ```bash
  make test-gpu
  ```

### Pre-commit hook (`tests/check/precommit_hook.sh`)

- **Runner**: [`tests/check/precommit_hook.sh`](check/precommit_hook.sh)
- **Description**: Checks hook restaging, partial staging, tool errors, optional tools, and the executable file mode. Each behavior test uses an isolated Git repository. `beautify.sh` must leave an already formatted C file untouched, mtime included: every `runtime/*.c` is a prerequisite of the runtime archive and so of all four bootstrap generations, so rewriting unchanged files on each commit would force a full rebuild on the next `make`.
- **Requirements**: `git` and `indent`. The test of Python restaging also needs `isort` and `yapf`; without them, the runner skips that one test and names the missing tools. A formatter that is on `PATH` but does not run still fails the hook, by design.
- **Running**:
  ```bash
  ./tests/check/precommit_hook.sh
  ```

---

## Topic notes

### RANGECK context isolation regressions

`tests/contract/rangeck_scope.sh` (native suite `rangeck_scope`) checks first-token
FOR/CASE and expression-call snapshots in parsed and typed ASTs using the
native `rangeck_metadata_check.pas` probe. Independent O0 IR guard counts
cover opposite inner/outer settings, branch/sibling independence and checked
value actuals. All four prior-assignment/FOR policy combinations execute
only valid bounds in both dialects at O0–O3; invalid checked endpoints must
abort before body output. Frozen legacy typed ASTs remain accepted. No invalid
unchecked loops are executed, and CASE no-match enforcement is not added.

### Scan builtin and small-string ABI regressions

`tests/corpus/golden/scan_builtins.pas` (a fixture with a dialect and O0–O3
matrix) tests SCANEQ/SCANNE
in both dialects at O0–O3 against independent expected outputs, including
signed skip counts, no-match boundary returns, empty/zero/out-of-range inputs,
selected strings and once-only ordered argument evaluation;
`golden/scan_shadow.pas` covers user shadowing, and the check fixtures in
`tests/corpus/checklit/scan/` cover arity/type errors and the explicit
INITCK/DEVICE boundaries with no published IR. The `runtime` unit suite runs `tests/unit/runtime_scan.c` directly
against the runtime, including the negative count endpoint.
`tests/corpus/golden/small_string_abi.pas` covers small STRING/LSTRING native
arguments/results, record wrapping and exhausted argument registers.
