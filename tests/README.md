# Test Suites for `native-pascal-1981`

This directory contains the automated test suites for the native Pascal 1981 compiler toolchain.

## Contents

- [Temporary-file isolation](#temporary-file-isolation)
- [Retained harness decisions and ownership](#retained-harness-decisions-and-ownership)
- [Shared support, parity and wrapper audit](#shared-support-parity-and-wrapper-audit)
- [Validation cost and concurrency](#validation-cost-and-concurrency)
- [MATHCK test map](#mathck-test-map)
- [MATHCK gap baseline](#mathck-gap-baseline)
- [Host descriptor contracts](#host-descriptor-contracts)
- [Opt-in overhead measurements](#opt-in-overhead-measurements)
- [INITCK support boundary](#initck-support-boundary)
- [Overview of Test Suites](#overview-of-test-suites)
- [Running the Routine Tests](#running-the-routine-tests)

## Temporary-file isolation

See the canonical [temporary-file ownership contract](../docs/temporary_files.md)
for harness workspace ownership, per-fixture/per-cell isolation, signal cleanup,
and the distinction between scratch data and persistent build reports. Keep
these rules together rather than duplicating them in individual suite guides.

### Retained Python temporary infrastructure

Keep `scripts/native_temp.py` and `tests/temp_hygiene.py` during the Python
reduction. They enforce/check the ownership contract, not arithmetic oracles.
Moving their Python into another module is not a reduction; replacing either
requires its own security/cleanup equivalence gate, not a source translation.

| Component | Purpose and invocation | Maintenance responsibility |
| --- | --- | --- |
| `scripts/native_temp.py` | Imported before any scratch allocation; validates the root, owns one interpreter workspace, redirects `tempfile` and child `TMPDIR`, and registers owner-only exit/signal cleanup. Not a CLI. | Maintainers changing Python workspace clients must preserve import-before-allocation, PID ownership, cleanup registration under blocked signals, and default INT / HUP / TERM exit behavior. Keep this module aligned with `scripts/temp-env.sh`, `runtime/temporary.c` and the canonical contract. |
| `tests/temp_hygiene.py` | Eleven infrastructure regressions for allocators, driver failure paths, concurrent fixtures and private proxy port publication. Run from the repository root with `./scripts/test-env.sh python3 tests/temp_hygiene.py` (or directly with `python3 tests/temp_hygiene.py`). `make test-native` includes it as `native-temp-hygiene`. | Maintainers of workspace allocators, driver staging, FILE storage and harness wrappers own the corresponding regressions; update them together with contract changes. Keep migration auditing and active-owner assertions, not merely “directory disappeared” checks. |

Current importing clients are `tests/temp_hygiene.py`, `tests/support.py`,
`tests/{initck,mathck}_overhead.py`, `tests/proxy/run_conformance.py`, and five
parity modules: `test_native_parity.py`, `test_native_device_units.py`,
`test_native_device_orchestration.py`, `test_native_host_uses_device.py`, and
`test_native_kernel_launch.py`. Keep their imports even when a different suite
loses its Python generator. Support/parity, proxy and benchmarks have separate
scope/ownership decisions; none is retired by this infrastructure decision.

The regression needs built native driver/stages, a C compiler (`CC`, default
clang), GNU/Linux process/filesystem tools and Python 3. Its unsafe-root case
uses the `bwrap` executable and skips when the sandbox probe cannot run;
Emacs allocator coverage is conditional on Emacs being installed. Report these
coverage limitations rather than treating a sandbox skip as security validation.

**Future replacement map:** preserve every row below before replacing either
retained component. Test names refer to `TemporaryHygiene` in
`tests/temp_hygiene.py`; detailed ownership rules remain in the canonical
contract, not in individual harness guides.

| Obligation | Existing regression / evidence |
| --- | --- |
| Reject symlinks, group/other-writable roots, foreign ownership and regular files; accept private roots and create safely under umask 002 | `test_unsafe_root_rejected`: driver, anonymous FILE, SysTempDirCreate, Python, shell, optional Emacs, each against seven root states in private `/tmp`; never make the real shared root unsafe. |
| Success/error exit and HUP/INT/TERM cleanup | `test_shell_exits_and_signals`, `test_python_exits_and_signals`, `test_runtime_owner_and_signals`; the shell child deliberately replaces its EXIT trap. Preserve checked exit statuses (Python signals require nonzero, not a specific status). |
| Fork and active-owner isolation | `test_runtime_owner_and_signals` exercises a forked C child's exit; `test_parallel_owner_survives` keeps another shell owner's file alive, and `assert_removed` preserves the active test workspace/shared root. Python's PID cleanup guard is code-reviewed here, **not** directly fork-tested; add an explicit Python fork regression before a replacement. |
| Driver multifile and pipeline failures, and termination while compiling | `test_driver_multifile_cleanup`, `test_driver_pipeline_failure_cleanup`: injected compiler/stage failures retain the real native pipeline, check status and remove the owned artifact directory only. |
| Anonymous FILE lifetime without visible names | `test_anonymous_file_storage`: readable/writable anonymous stream, removed path/directory, close and fatal TERM. |
| Concurrent fixture data isolation | `test_parallel_fixture_cells`: 16 copies of `vintage_enum_io.pas` at eight workers, all 16 required to pass. |
| Migration coverage | `test_migration_audit`: shell `mktemp` users source temp-env, test Python `tempfile` users import native_temp, Pascal tests avoid literal `/tmp/` paths. This textual audit does not itself prove import ordering or security. |
| Allocation/registration signal window and redirection | Review `native_temp.py` signal masking, atexit registration, PID guard, `tempfile.tempdir` and exported `TMPDIR`, plus shell process-group supervision and runtime async-signal-safe cleanup. Existing exit/signal tests are not a deterministic interrupt-at-allocation test or an independent child-TMPDIR assertion; extend coverage before replacing these mechanisms. |

No replacement is scheduled here. SIGKILL, immediate `_exit` and power-loss
cleanup remain outside the guarantee; never erase the shared namespace to
simulate successful cleanup.

## Retained harness decisions and ownership

Python reduction changes implementation, not coverage. The decisions below
retain the corpus/audits and intentionally keep infrastructure, measurements
and structural checks where a replacement has not demonstrated equivalence.

| Family / disposition | Purpose and invocation | Maintenance responsibility |
| --- | --- | --- |
| Corpus twins: retain full corpus, migrated to shell | `./scripts/test-env.sh ./tests/mathck_twins.sh`, also native-suite-mathck_twins; [on/off twin contract](#mathck-onoff-twins). | MATHCK/corpus maintainers preserve fixture discovery, dialect/args/stdin handling, per-cell isolation, nonempty/result gates and paired outcomes. Do not prune cases to remove Python or treat unchecked overflowing outputs as oracles. |
| G1–G29 baseline: retain classification audit, migrated to shell/JSON | `./scripts/test-env.sh ./tests/mathck_baseline.sh`, also native-suite-mathck_baseline; [gap baseline](#mathck-gap-baseline). | MATHCK maintainers own `mathck_baseline.json` and fixtures together: keep all gap IDs, independently justified outcomes, bounds and compile-only categories; reclassify a fixed gap in the fixing change. Observed gaps are not language contracts. |
| Bootstrap source audit: retain, migrated to shell/jq/awk | `./scripts/test-env.sh ./tests/mathck_bootstrap_audit.sh`, also native-suite-mathck_bootstrap_audit; [bootstrap contract](../docs/bootstrap_subset.md#self-hosting-arithmetic). | Compiler/pasboot maintainers own unchecked label-key scope, restored flags, actual wide-limit IR, gen1–gen4 label keys, malformed directives and declared runtime/cell totals. Do not confuse this focused audit with the destructive `test-bootstrap` gate. |
| No-core infrastructure: retain Python | `./scripts/test-env.sh ./tests/test_no_core.py`, mandatory `native-no-core`. Tests launcher/descendant dumpability, direct SIGABRT/stdout/stderr, opt-out and mixed destructive-goal rejection. | Test-launcher maintainers own `scripts/test-env.sh`, `tests/support/no_core.c`, shim publication and regression together. Preserve exact signals/diagnostics and per-exec suppression without production-runtime or system-wide crash-setting changes. Non-Linux dumpability coverage skips explicitly. |
| Overhead measurements: retain both Python drivers, opt-in | `python3 tests/initck_overhead.py` and `python3 tests/mathck_overhead.py`; [method, fixtures and reports](#opt-in-overhead-measurements). Neither is a mandatory test. | Benchmark maintainers own inputs, independent correctness checks, timing/size/memory method and environment/revision reporting. Keep raw samples and limitations; do not turn host timings or reference-compiler outputs into numeric correctness thresholds. |
| Structural AST: retain six inline Python blocks; native astcompare/checklit also remain | Owning suites and obligations below; [native AST comparison runner](astcompare.sh) is separate from these relational checks. | AST/read-site maintainers preserve schema/provenance, exact mutation scope/counts and traversal semantics. A generic JSON walk or ordered text matcher is not automatically an equivalent checker. |

The no-core regression has no Pascal-compiler/bootstrap requirement: it uses the
independently built test-only shim (and Python child processes). Its direct
execution also checks the launcher itself, so it removes enclosing preload and
opt-out settings before its probes; static/set-ID preload limitations still
apply. It does not need native_temp because it allocates no scratch workspace.

**Inline Python ownership:** the maintainer of each owning shell suite owns its
retained blocks and invokes them with
`./scripts/test-env.sh ./tests/<suite>.sh`; `make test-native` runs those suites.
Keep the existing caller flags, compile/runtime matrices and disabled-invalid
compile-only paths when changing any block.

| Structural blocks / owning suite | Purpose and maintenance obligation |
| --- | --- |
| Two in `initck_contract.sh` | Legacy/mixed read-flag mutation and exact provenance before/after typecheck: retain traversal alternation, absent snapshots, excluded resolved_type traversal and true/false mixture. |
| Two in `initck_scalar.sh` | Parser/typed read location and enabled flag assertions, typed zero-selector Designator/no-location variants, and recursive legacy flag removal. Preserve the typed-tree origin and don't remove enabled flags when stripping coordinates. |
| One in `initck_routines.sh` | Strip only enabled RETURN/Block snapshots, exactly two; preserve no-guard/default-return and original guard-count checks. |
| One in `stage_cli.sh` | Remove only read_location columns for structural equality, require nonempty wide columns exactly {40000}; retain the suite's conditional pass/fail handling. |

Nineteen retained IR/dataflow/mutation/presence blocks belong to
`initck_{definite,external,heap,producers,routines,scalar,validation}.sh` and
`super_new_contract.sh`. These owners must preserve function scope, first/last
occurrences, SSA identity, branch/unreachable shape, state publication, helper
counts and mutation match gates as applicable, not just substring order.
Two incidental text blocks remain: the ABI normalizers in `initck_abi.sh`
and `initck_routines.sh`. Retain their ordered signatures/call multiplicity,
SSA-name normalization differences and layout assertions until equivalent
checks are demonstrated. This ownership map covers all 27 remaining inline
sites, not a promise to keep them indefinitely or a Python-free suite claim.

The four diagnostic-column calculations now use literal `awk` indexing on
these ASCII fixtures: routines selects the last needle on the positive selected
line (including overlapping matches), while scalar selects the second x for
self-update, first for REPEAT and last otherwise, with the two-space indentation.
Missing line/token fails rather than fabricating a column. Needles enter via
the environment, not regex or awk escape interpretation. The external suite's
`probe_ir` buffers the first probe definition through the line before its
column-zero closing brace; it requires both header and close before emitting
anything and retains the final newline (native LF and CRLF input). These are
fixture-specific text operations, not a Unicode source-column or LLVM parser.
Maintainers changing fixture encoding/layout or emitted IR conventions must
review these assumptions alongside the exact diagnostic/IR consumers. The
remaining relational and structural blocks still require Python.

**Reference refresh tooling:** retain `scripts/update-reference-depth.py` as
maintenance, not a routine test. Run `PYTHONPATH=. ./scripts/update-reference-depth.py`
only for intentional fixture regeneration. Depth-test maintainers own its
oversized source/AST generation, bypassed reference limits, restored Python
recursion limit, and review of `tests/reference/depth/*`; confirm the native
`./scripts/test-env.sh ./tests/depth.sh` assertions rather than blessing the
reference's behavior as the contract. It writes persistent fixtures, so it
has no native_temp import. The shell refresh entry points
`update-reference-{ast,codegen,gpu}.sh` likewise retain reference-compiler Python
as explicit maintenance: review source/JSON changes and run the owning native
AST/checklit/GPU suite (report GPU prerequisite skips). Routine test recipes
consume frozen inputs, not these refresh commands. Their invocation details
remain in the corresponding suite sections and script headers.

Together with the [temporary infrastructure](#retained-python-temporary-infrastructure),
[proxy](#completion-proxy-conformance-retained) and
[optional parity/support](#3-parity-test-suite-testsparity----opt-in-retained)
sections, this accounts for every retained standalone Python component.
The audit below records actual shared-support/wrapper boundaries and unresolved
findings. Any future removal or lifecycle correction still needs its own
validation; documentation is not a runtime validation gate.

### Shared support, parity and wrapper audit

Keep shared support: its two direct clients are
`parity/test_native_parity.py` (`RUNTIME_LIB`) and
`parity/test_self_host_record_layout.py` (project/compiler/link/skip helpers).
Importing `tests/support.py` is **not passive**: it imports the reference front
end, installs native_temp, probes GPU/toolchain capabilities and may build a
missing runtime archive. Static inspection should not import it merely to
count assertions. Reference lowering is lazy in `compile_pascal_file`, but
capability probes and runtime setup are eager. Project helpers clean their
sources/artifacts in finally/context-manager paths; parse/typecheck helpers
unlink their generated source after use. These helpers accept trusted test
paths, not arbitrary untrusted project manifests.

The retained parity modules contain 53 test methods (18 depth, 9 stage/link
parity, 1 record-layout, 5 DEVICE units, 2 orchestration, 6 host USES, 12
kernel/launch). This is a static method inventory, **not** a collected test or
matrix-cell count: decorators, parameterization and fixture/subTest loops
change actual execution. Preserve each group's distinctions:

- Depth: reference parser boundaries/sibling reset, forged deep ASTs through
  serialization into reference checker/codegen, reference CLI diagnostics,
  and parsing five self-hosting source files. Despite its old module prose,
  it does not compare native Pascal depth constants with Python constants.
- Stage parity: parser/typed-object/rejection comparisons after specific trivia,
  INDEXCK, MATHCK and resolved_type normalization; REAL32 tag checks; five
  self-hosting sources; clang assembly and one linked-output comparison.
  Assembly validity is not runtime equivalence. INITCK/reference divergences
  remain intentional, not a reason to broaden normalization silently.
- Layout: ten literal historical RECORD snapshots, **not** automatic discovery
  or a fidelity check against today's decomposed source units. Retain per-field
  LLVM TargetData offsets, alignment/tail padding, each compiler's SIZEOF and
  the optional cross-compiler size comparison as distinct obligations.
- DEVICE units: three compilation-unit roots to PTX, six transcendental
  rejections plus CPU libm acceptance and lowercase JSON bypass, NEW/DISPOSE
  forged DEVICE AST rejection. No real GPU execution occurs here.
- CPU orchestration: allocation/copy/launch/copyback output plus one forged
  DEVFREE rejection. The other host-only builtins are mentioned in prose,
  but are not individually rejection-tested by this module.
- Host USES: imported ABI/thunk and exact call count, linked six-thread output,
  forged host ADS/missing-header rejection and both alias/original binding
  cases. Kernel/launch: read/write/helper attributes, alignment/extent, PTX,
  noalias opt-in, host exclusions, registry/thunk multiplicity, CUDA host
  shape and both geometry forms' linked output (6, 66).

Five parity modules import native_temp directly; record-layout gets it through
support; depth uses pytest's `tmp_path`. All ten direct native_temp clients
listed above import it before tempfile allocation. They use its default temp
root except conformance's per-startup port directory, explicitly nested in its
owned `_log_dir`. native_temp's own allocation is explicitly in its validated
namespace. Pytest fixture placement is not proved by that import
inventory: an isolated depth-module run has no native_temp import, and pytest
`--basetemp` can override its placement. Preserve the distinction between a
private source/artifact directory and runtime data isolation: support/link-run
and CPU-device executions do not all set `cwd` to their project workspace.

Make keeps `test-reference-parity` opt-in with no native-build prerequisites.
Native stage paths default to `bin/` or the `NATIVE_*` overrides. Capability
skips are not comprehensive dependency handling: record-layout imports
llvmlite before its skip decorator, some clang/link/run calls and GPU probes
lack timeouts, and DEVICE/launch classes gate on codegen executability, not
all link/backend prerequisites. Missing reference/toolchain dependencies can
fail collection/execution rather than skip. Record actual failures/skips when
running this historical comparison; do not claim all optional checks ran.

Proxy wrapper ownership is separate from report destinations. `run.sh`,
`oneshot.sh`, `corpus_smoke.sh`, `transforms_check.sh` and
`corpus_reference_check.sh` all source temp-env; their work, runner binaries,
logs and shell-created port files are in supervised workspaces. Six build
wrappers compile native Pascal units into caller-supplied output paths and
allocate no shell scratch. Four require the fixture-directory cwd; the two
conformance builders derive it from their own path. `tests/run.sh` supplies
that cwd and absolute compiler/output paths to fixture builders, but its
default discovery does not include `tests/proxy`. Explicit native wrapper
checks still own these cases; do not remove them because native-golden did
not discover them. `test-proxy` invokes all five wrappers; Make concurrency
and that target's separation from `test-native` remain unchanged.

| Audited boundary / responsible maintainer | Current behavior, coverage or required follow-up |
| --- | --- |
| Private conformance port publication / proxy harness | `Harness.start_stub` publishes `port` in a private per-startup TemporaryDirectory inside its owned `_log_dir`. Context cleanup removes the directory on success or exception; a late file write cannot recreate that missing parent. `test_proxy_stub_port_publication` covers ownership/mode, repeated success, spawn failure, early exit, empty/malformed publication, unready listener and timeout with injected children, plus real repeated/concurrent listeners in one PID. This does not prove child-tree reaping or add a child-registration signal guarantee. |
| Daemon supervision / proxy harness and shell wrapper owners | `build_report` stops registered children in finally; stderr files avoid undrained PIPE deadlocks. `stop_all` terminates/waits then kills on timeout but does not wait after kill or supervise an entire descendant tree. oneshot/smoke cleanup kills without waiting. Workspace cleanup alone is not child-reaping proof; retain bounded lifecycle/signal tests for any correction. |
| Report case uniqueness / proxy protocol maintainers | `compare` checks the union of case-name sets and exact non-note records, but dict construction collapses duplicate names. Calibration is compared via the report; corpus/dead-health checks also use the native replay runner. Native/golden checks do not establish duplicate rejection in the Python comparator. Add an explicit uniqueness gate only with a focused regression, not by claiming coverage already exists. |
| Shared helper data/paths and optional test bounds / parity maintainers | Trusted project paths are not containment-validated; several executable runs use inherited cwd and lack timeouts. Import/capability skips and pytest tmp_path do not prove per-fixture runtime data isolation. Any hardening needs targeted failure, cleanup and caller-equivalence checks, without turning reference parity into a mandatory oracle. |

The private-port regression can be run without compiler/GPU prerequisites:
`./scripts/test-env.sh python3 tests/temp_hygiene.py TemporaryHygiene.test_proxy_stub_port_publication`.
Its injected timeout avoids a 20-second wait; real listener probes retain the
harness bounds. Diagnostics remain in owned logs and native_temp removes the
process workspace at exit. It neither changes golden comparison nor supervises
children beyond the existing harness teardown.

The other rows are retained audit findings, not retired assertions or passed
lifecycle guarantees. Existing temporary-infrastructure regression gaps remain open. Fixes
may be bounded separately without removing support, reducing matrices or
rerunning unchanged optional parity during every documentation slice.

## Validation cost and concurrency

`make -jN` parallelizes Make targets, not shell loops. `make test-native`
passes `TEST_JOBS` to the main golden/integration/dialect runner (default
8); override with `make -j8 test-native TEST_JOBS=8`, or use `TEST_JOBS=1`
for serial debugging. The fixture-based MATHCK suites run their own units in
parallel; the other suites run their cells sequentially. These are independent
concurrency budgets, not a shared Make job pool.

`make test-native` first builds every tool it needs with `BUILD_JOBS`
(default 8) parallel jobs: the runtime objects, pasboot and the four stages
within each bootstrap generation build concurrently, while generations still
build in order. A full rebuild takes about 205 s this way, against about
310 s serially. It then runs every suite as its own Make target, up to
`TEST_SUITE_JOBS` (default 6) at once, longest first, with the many-worker
MATHCK suites interleaved among the single-core ones, and with `make
--output-sync` keeping each suite's output together. On a 16-thread machine
with every tool current, the suites take about 103 s, against 205 s one at a
time. Use `TEST_SUITE_JOBS=1` to run them one at a time (in the Makefile's
`NATIVE_SUITES` order) when debugging. As with any `make -j`, a failure
stops new suites from starting while running ones finish. Eight slots, or
running the many-worker suites at lower priority, measured slower.

Test Make targets launch suites through `scripts/test-env.sh`. On Linux,
this preloads a small **test-only** constructor that sets `PR_SET_DUMPABLE=0`
after each dynamic `exec`, including descendants. A zero core-size limit
alone does not stop piped core handlers such as Ubuntu Apport: each expected
abort can otherwise spend about a second reporting a crash. The launcher
preserves exit signals, stdout and stderr; production runtime code is untouched.
Other platforms only use a zero core-size limit. Static/set-ID executables
cannot rely on this preload mechanism.

Use the same environment for standalone focused tests:

```sh
./scripts/test-env.sh ./tests/mathck_divmod_safety.sh
./scripts/test-env.sh ./tests/mathck_constant_folding.sh
```

Set `PASCAL_TEST_CORES=1` to opt out for crash debugging (subject to your
shell/system core limits). The Linux shim is built/cached independently at
`build/test-no-core.so`; this never requires a compiler bootstrap. Existing
`LD_PRELOAD` entries are preserved. No system-wide crash-report setting changes.

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

## MATHCK test map

Every script below runs in `make test-native` (concurrently; see above) and can be run
alone through `./scripts/test-env.sh ./tests/<name>.sh`. They need built
`bin/` tools and each suite's shell/native dependencies (including `jq` for
JSON checks), not Python 3. The overall native gate still requires Python for
retained infrastructure and INITCK/structural checks. Oracles come from exact arithmetic and the
[MATHCK contract](../docs/dialect_notes.md#mathck-integer-overflow-and-division-checks-both)
in the dialect notes, not from earlier compiler output.

| Contract area | Script | Details |
|---|---|---|
| Gap inventory G1–G29, observed vs. expected | `mathck_baseline.sh` | [baseline](#mathck-gap-baseline) |
| WORD division and ordering are unsigned | `mathck_word_scalar.sh` | [WORD prerequisites](#scalar-word-arithmetic-prerequisites) |
| FOR stops at the final value without MATHCK | `mathck_for_endpoints.sh` | [FOR endpoints](#for-endpoint-termination) |
| DIV/MOD zero divisor and MIN/-1, both settings, no LLVM UB | `mathck_divmod_safety.sh` | [DIV/MOD safety](#scalar-divmod-safety-prerequisite) |
| Constant folding: truncating DIV/MOD, exact fit, constant zero divisor | `mathck_constant_folding.sh` | [constant folding](#constant-divmod-folding-prerequisite) |
| MATHCK-sensitive arithmetic in the compiler sources and pasboot | `mathck_bootstrap_audit.sh` | [bootstrap audit](#bootstrapself-hosting-arithmetic-audit) |
| Per-operation `mathck`/`op_location` snapshots in the AST | `mathck_metadata.sh` | [metadata](#per-operation-mathck-metadata) |
| Scalar `+ - * DIV` and negation at every width, trap vs. wrap, constants | `mathck_scalar.sh` | [overflow](#mathck-overflow-enforcement), [fixtures](#mathck-scalar-fixtures) |
| O0 guard order of each checked operation | `mathck_overflow.sh` | [overflow](#mathck-overflow-enforcement) |
| SUCC/PRED/ABS/SQR, RANGECK domains, SADDOK family | `mathck_builtins.sh` | [builtins](#mathck-builtins) |
| Mixed widths widen; mixed INTEGER/WORD rejected (G24) | `mathck_mixed_width.sh` | [mixed widths](#mathck-mixed-widths) |
| Integer VECTOR lanes and VSUM/VPROD | `mathck_vector.sh` | [VECTOR](#mathck-vector-lanes) |
| TRUNC/ROUND range check (always on, not MATHCK) | `trunc_round_range.sh` | [TRUNC/ROUND](#truncround-range-g26) |
| NVPTX `DEVICE arithmetic` boundary; CPU DEVICE checked | `mathck_device.sh` | [DEVICE](#mathck-in-device-code) |
| Pointer `+` offsets and `[C]` values at the boundary | `mathck_address_arith.sh` | [address arithmetic](#mathck-address-arithmetic-boundary) |
| Exact located messages, distinct from RANGECK/INDEXCK/INITCK | `mathck_diagnostics.sh` | [diagnostics](#mathck-diagnostics) |
| Non-overflowing programs identical under MATHCK+ and MATHCK- | `mathck_twins.sh` | [on/off twins](#mathck-onoff-twins) |
| 32767, -32768, 0, 65535 and edge results never trap | `mathck_boundary_values.sh` | [boundary values](#mathck-boundary-values) |
| Proven checks fold, unprovable stay; whole-vector check shape | `mathck_optimization.sh` | [optimization](#mathck-optimization) |

MATHCK also shapes fixtures outside these scripts: the checklit vector
shapes (`checklit/vector_arith.pas`, `vector_reduce.pas`), the NVPTX checklit
fixtures (`checklit/device_*.pas`) and the CUDA tests (`gpu/vadd.pas`,
`gpu/aggregate.pas`) carry `{$MATHCK-}`, because they pin unchecked SIMD
instructions or must compile for the GPU. `make test-gpu` runs the CUDA
tests. `tests/mathck_overhead.py` (opt-in, not in `make test-native`)
measures code size and runtime with MATHCK on and off; see
[opt-in measurements](#opt-in-overhead-measurements).

## MATHCK gap baseline

`./tests/mathck_baseline.sh` (also in `make test-native`) runs the persisted
G1–G29 classification inventory against the native compiler. Requires `jq` and built `bin/` tools. The manifest is
[`mathck_baseline.json`](mathck_baseline.json); sources are in
[`fixtures/mathck/`](fixtures/mathck/), with G29 reusing the existing READ
input-overflow goldens. Every applicable probe runs in both dialects at O0/O2;
wide types and extended constant probes are extended-only.

This is a **classification audit, not a conformance suite**; the focused
suites below own the contracts. Each of the 46 manifest entries names its gap
ID, classification, oracle (where safe) and target. Split entries cover WORD
add/sub/multiply, signed/unsigned DIV/MOD by zero, MIN DIV/MOD, SUCC/PRED, the
four OK builtins, three wide INTEGER widths, constant overflow forms, and
TRUNC/ROUND. The manifest's `baseline` field records where the inventory was
first taken; it is provenance, not a statement about current behavior.

- `correct-runtime-error` (24 entries: G1–G6, G7 DIV, G8, G10–G12, G20, G26,
  G29) requires the exact diagnostic and flushed stdout prefix, not a
  specific signal.
- `correct-output` (14: G7 MOD, the four G13 OK builtins, G14–G19, G21, G22,
  G28) requires exact output.
- `correct-reject` (5: G9, G23 add/mul/SUCC, G24) requires compile-time
  rejection.
- `known-gap-reject` (1: G25, the deferred
  [`ORD(WORD)` conversion](../docs/dialect_notes.md#deferred-ordword-conversion-gap-g25))
  pins the current rejection. The fixing change must flip it; the gap never
  becomes the contract.
- `out-of-scope-output` (2: G27 `1.0 / 0.0` is `INF`; G27.overflow, REAL
  overflow is `INF`/`-INF` under MATHCK+) pins IEEE results without claiming
  MATHCK protection, since REAL arithmetic is outside MATHCK.

The suite also accepts `known-gap-output` (wrong but defined output),
`known-gap-crash` (signal termination without a diagnostic),
`known-gap-compile-only` (compiled, never executed) and `known-gap-timeout`
(bounded nontermination) for newly recorded gaps; no current entry uses them.
No UB-derived output is ever an oracle.

Unexpected acceptance, new diagnostics, or loop termination deliberately fail
the baseline: inspect the change and update the corresponding gap entry rather
than weakening the oracle. Execution has a five-second timeout (one second for
a `known-gap-timeout` entry), compilation a thirty-second timeout, and
temporary artifacts are removed.
The inventory itself does not change MATHCK scope decisions or frozen ASTs.

### Scalar WORD arithmetic prerequisites

`./tests/mathck_word_scalar.sh` (also in `make test-native`) checks unsigned
scalar DIV/MOD and ordering at every WORD-family width. Its native expected
outputs run in both dialects for WORD and extended mode for WORD8/32/64,
at O0/O1/O2/O3 with both MATHCK settings (24 runtime cells). Coverage includes
high-bit/max/low values, both operand orders, all ordering predicates and
EQ/NE, literal adaptation, unsigned width promotion, signed controls and CASE.
O0 IR asserts unsigned instructions at every width and preserved wider
zero-extension/signed array bounds comparisons. Set membership bounds remain
unsigned; supported INTEGER membership and existing WORD admission rejections
are tested. See the [WORD comparison boundaries](../docs/dialect_notes.md#word-arithmetic-and-comparison-boundaries)
and [WORD to REAL rules](../docs/dialect_notes.md#word-to-real-conversion).
The same fixtures pin FLOAT, mixed REAL +/* and wide maxima; O0 IR requires
`uitofp` at 8/16/32/64 bits. G14–G17 and G21 are correct-output oracles.
This suite is not overflow enforcement or zero-divisor safety: all executed
divisors here are nonzero. Dedicated folding, mixed-type and division-safety
suites enforce those separate implemented contracts.

### FOR endpoint termination

`./tests/mathck_for_endpoints.sh` (also in `make test-native`) checks that a
FOR loop leaves at its final value instead of stepping past it and wrapping.
Iteration counts are the oracle; the post-loop control value is undefined
(manual 9-17) and never printed. `fixtures/mathck/for_endpoints.pas` runs in
both dialects and `for_endpoints_wide.pas` in extended mode, each at
O0/O1/O2/O3 with both MATHCK settings, covering both directions at the
extremes of INTEGER, WORD, CHAR, BOOLEAN, an enumeration and the 8/32/64-bit
widths, WORD limits across the sign bit, zero-iteration loops, variable and
mutated limits and BREAK. A `$RANGECK+` subrange control variable keeps the
same termination. O0 IR asserts the `for_inc` equality exit on INTEGER and
WORD loops and unsigned WORD ordering. G18 and G19 are correct-output
oracles; FOR termination is independent of MATHCK.
Python-reference parity is not used.

### Scalar DIV/MOD safety prerequisite

`./tests/mathck_divmod_safety.sh` (also in `make test-native`) runs
checked-in fixtures for all signed/unsigned scalar widths (16-bit in both
dialects, 8/32/64-bit extended) under both MATHCK settings at O0–O3, as
independent parallel units with declared cell totals: 16 defined-result
cells, 160 zero-divisor cells, 4 guarded-IR, 4 NVPTX, 4 host-guard and 4
legacy-coordinate checks.

- `fixtures/mathck/divmod_<dialect>_{checked,unchecked}.pas/.out`: signed
  MIN built at run time, MIN MOD -1 returning zero under both settings, MIN
  DIV -1 returning MIN only in the unchecked fixture, the truncating sign
  table (quotient toward zero, remainder `a - q*b`) and unsigned high-bit
  values. Their `-S -O0` IR must divide only by a sanitized
  `select i1 …, iN 1, iN …` defined earlier in the function, after the
  `div.bad`/`div.ok` branch (an `awk` pass per function), at least four
  divisions per width, with no `poison` or `undef`.
- `fixtures/mathck/divmod_zero.pas` + `divmod_zero.cases`: a template and
  one row per type and operator with the exact diagnostic. A dynamic zero
  divisor fails under both settings with nonzero status, flushed stdout
  `prefix`/`left`/`right` (single left-to-right operand evaluation) and the
  DIV/MOD token's line and column from the operator snapshot.
- A legacy typed AST (snapshots removed with `jq`) keeps exactly one
  zero-divisor guard and reports `line 0 column 0`; the snapshot AST reports
  `line 9 column 21` (both checked in IR, both dialects). Frozen ASTs are
  unchanged and obey the same safe unchecked lowering.
- `fixtures/mathck/divmod_device.pas`: NVPTX scalar DIV/MOD fails before
  output under either setting, with the exact located MATHCK boundary
  (MATHCK+) or mandatory-safety (MATHCK-) message; host codegen of the same
  AST keeps the guard.

Neighbouring contracts live elsewhere: MIN DIV -1 overflow under MATHCK+ is
in [overflow enforcement](#mathck-overflow-enforcement), constant zero
divisors are rejected in the [constant-folding suite](#constant-divmod-folding-prerequisite),
and VECTOR lane DIV/MOD safety is in [VECTOR lanes](#mathck-vector-lanes).

### Constant DIV/MOD folding prerequisite

`./tests/mathck_constant_folding.sh` (also in `make test-native`) checks
truncation toward zero and dividend-signed MOD in both folders, independently
of MATHCK: 24 runtime cells at O0–O3 and 160 constant-zero rejection cells,
each with exactly one `Constant division by zero`.
Literal and named constants, all sign combinations, exact division, MIN MOD
-1, G22, large negative array indices and mixed-width/assignment adaptation
are covered. Direct parser-derived AST probes exercise CONST values consumed
by CASE labels and array bounds, and test zero rejection in the typechecker
and codegen independently. The source CONST/CASE/bound grammar does not admit
binary expressions, and these tests do not broaden it.

The fixtures are in `fixtures/mathck`: `constfold_twins.pas/.out` (each row
folded as a constant and computed at run time; both dialects, the suite
prepends either setting), `constfold_zero.pas/.err` (a template for the 16
zero-divisor expressions, and for four whole statements from the suite's
`zero_statements`: an assignment, an unspaced divisor, a variable dividend and
a zero divisor nested in a larger expression; exact stderr and no output file,
O0/O2) and
`constfold_consumers.pas/.out`. `constfold_ast.pas` is parsed, and a `jq`
filter in the suite replaces its CONST value with `-7 DIV|MOD 2|0`, taking
the node discriminator from the parser's own output. The typechecker and
codegen each then succeed (codegen emits `i16 -3` or `i16 -1`, without the
other operator's result or poison) or print exactly
`constfold_ast_{typechecker,codegen}.err` with empty stdout. The suite runs
its units in parallel with declared totals: 16 twin, 8 consumer, 128 zero,
32 zero-statement and 4 AST cells.

G9 is a correct compile-time rejection and G22 a correct-output oracle.
The wide-folding golden expects `-5 DIV 2 = -2` and `-5 MOD 2 = -1`, not
Python floor semantics. See the
[constant consumer invariants](../docs/dialect_notes.md#constant-divmod-and-consumer-invariants).

### Bootstrap/self-hosting arithmetic audit

`./tests/mathck_bootstrap_audit.sh` (also in `make test-native`) pins the
source dependencies in the [bootstrap contract](../docs/bootstrap_subset.md#self-hosting-arithmetic): narrow
MATHCK- label-key expressions and restored MATHCK+ counters, wide i64 limit
construction in actual compiler-unit IR, label AST keys at generations 1–4
in both dialects, and 16 high-bit LABEL/GOTO runtime cells (both settings,
both dialects, O0–O3). It also runs pasboot's ignored-MATHCK wrapping fixture
at Clang O0–O3 and checks malformed settings. `make test-pasboot` runs the
same fixture at O1 plus the standard bootstrap feature/rejection matrix.
The label program is `fixtures/mathck/bootstrap_labels.pas/.out`. The token
flags and label keys are checked with `jq`, the IR function bodies are
extracted with `awk`, and a malformed setting must print exactly
`<path>:1: malformed $MATHCK`. Units run in parallel with declared totals: 1
flags, 4 wide-limit functions, 8 label-key, 4 pasboot, 4 malformed and 16
native cells.
MATHCK+ overflow diagnostics for user arithmetic (G1–G5, G7 DIV, G20) are in
[MATHCK+ overflow enforcement](#mathck-overflow-enforcement).

### Per-operation MATHCK metadata

`./tests/mathck_metadata.sh` (also in `make test-native`) checks the
per-operation MATHCK snapshot. Arithmetic BinOp (`+ - * DIV MOD`) and
sign-minus UnaryOp nodes carry `mathck` and `op_location` (`line`, `column`)
captured at the operator token, before the right operand or the signed term
is parsed; SUCC/PRED/ABS/SQR FuncCall nodes (any letter case, expression or
CONST context) carry the same fields from the function-name token, before
the arguments. [`mathck_metadata_check.pas`](mathck_metadata_check.pas)
prints one line per such operation from both the parser and typechecker
output and rejects missing snapshots or snapshots on other operators and
calls. Expected listings are the `.out` files beside
`fixtures/mathck/metadata_{ops,builtins,transitions,const}.pas`; all but the
CONST fixture run in both dialects. `metadata_transitions.pas` covers active
and skipped `$IF` branches (skipped directives and a skipped missing include
take no effect) and includes that share the caller's PUSH stack, including an
include inside an expression; operations in an include report that file's
line numbers. Frozen typed ASTs with arithmetic must carry no snapshot and
still compile (legacy unchecked nodes). Typed output is also compiled to
IR. The snapshots are syntactic: set and REAL `+ - *`, REAL ABS/SQR and CHAR
SUCC carry them too; codegen decides applicability (see below). Frozen-AST
and parity comparisons ignore both keys.

### MATHCK+ overflow enforcement

`./tests/mathck_scalar.sh` (also in `make test-native`) runs checked-in
[fixtures](#mathck-scalar-fixtures) at every scalar width (16-bit in both
dialects; extended 8/16/32/64-bit), signed and unsigned, at O0–O3. Checked
`+ - *`, signed `DIV` and unary minus must fail with `runtime error: MATHCK
<signed|unsigned> overflow in <op> at line L column C (left=…, right=…)`,
after flushing the stdout prefix and evaluating each operand once, left to
right (unary minus reports `(operand=…)`; WORD-family negation succeeds only
for zero). Boundary results that fit must not trap under either setting,
including signed results of exactly MIN (`-32767 - 1`, `-16384 * 2`). Signed
`MIN DIV -1` fails as `signed overflow in DIV` under MATHCK+ (after the
mandatory zero-divisor test) and returns MIN under MATHCK-; `MIN MOD -1` is 0
under both. The same overflowing operations under `{$MATHCK-}` must print the
result wrapped at its width, identically at O0–O3. Their O0 IR must use plain
`add/sub/mul` with no `nsw`/`nuw`, overflow intrinsic, failure call, `poison`
or `undef`. The MATHCK+ source with `mathck`/`op_location` stripped from its
typed AST is a legacy AST: codegen must emit the same unchecked IR, and the
linked program must print the wrapped results at O0–O3.
`./tests/mathck_overflow.sh` (also in `make test-native`) checks that at O0
every checked operation's IR must branch on the intrinsic's overflow bit to a block that
calls `pas_math_overflow` and ends in `unreachable`, and the result may be
extracted only in the success block; a checked signed DIV branches on
`%div.min` before dividing. It compiles `fixtures/mathck/guards.pas` (`{TYPE}`
= all ten scalar type/dialect pairs) and follows each check to its branch
targets with an `awk` pass over `main`, since `checklit.sh` matches unordered
lines. [`fixtures/mathck/twin_arith.pas`](fixtures/mathck/twin_arith.pas)
(GCD, Fibonacci, MIN/MAX boundaries, WORD sums, truncating DIV/MOD) never
overflows and must print `twin_arith.out` under both settings, both dialects
and O0–O3. Constant operands: fully constant overflows (`WRITELN(32767 + 1)`,
`WRITELN(-N)`, `(M + 1) - 1`, the operand of `k := i + (M + 1)`, INTEGER8 and
INTEGER32 forms) must be rejected as "integer constant out of range" with no
IR under either setting; valid constants print their exact value at the
context type (`j := i + (M + 1)` is 32773 for INTEGER32 `j`); a partially
constant `i + (M - 4)` traps under MATHCK+ and wraps under MATHCK-, and so
do operations on enumeration constants (`ORD(blue) * 20000`, `32767 +
ORD(green)`, negation and `DIV` by -1), which the typechecker does not fold,
so codegen must not exempt them; ORD of an enumeration is INTEGER, so
`ORD(e) * 20000` traps rather than being checked at 32 bits and truncated.
Non-overflowing enumeration-constant operations print their exact values.
Wide
extremes are built at run time because INTEGER64 literals above 2^53 lose
precision.

### MATHCK scalar fixtures

The fixtures are `fixtures/mathck/scalar_<type>_*` for the eight integer
types (INTEGER and WORD in both dialects, the others extended), each with its
exact or wrapped result written in a comment beside the operation:

- `_ok.pas`/`.out`: boundary results that fit, under both settings (the
  script prepends the directive);
- `_wrap.pas`/`.out`: the overflowing operations under MATHCK-. The same file
  is the IR input: its `-S -O0` output, and codegen of its MATHCK+ typed AST
  after `jq` strips every `mathck`/`op_location` key, must both be plain
  arithmetic at the type's width;
- `_fail.pas`/`.expected`: one trap per case number read from stdin; the
  transcript holds a nonzero status, the stdout prefix with each operand
  printed once, and the exact located diagnostic.

`scalar_constants.pas` is a template whose `{STATEMENT}` and `{WIDE}`
comments the script replaces from the rows of `scalar_constants.cases`: each
row is a constant rejection (exact stderr, no IR file), an exact constant
value, or a partially constant trap (`i + (M - 4)` and the enumeration-constant
rows), in the dialects the row names (both, for every current partial and
enumeration row). INTEGER64 and WORD64 values beyond
2^53 are built from 32-bit halves. The script removes each binary and IR path
before writing it, so a stale artifact cannot pass, runs its units in
parallel, and fails unless every cell count matches the totals it declares.

### MATHCK builtins

`./tests/mathck_builtins.sh` (also in `make test-native`) covers the scoped
builtins with the same oracle style, O0–O3. Integer-family SUCC/PRED/ABS/SQR
at every width, signed and unsigned, both dialects: boundary results that
fit succeed under both settings (`ABS(MIN + 1)`, the largest square, a
WORD-family ABS of a high-bit value, which is the value itself); results
past the type's range (SUCC of MAX, PRED of MIN, signed `ABS(MIN)`, SQR of
`isqrt(MAX) + 1`) fail under MATHCK+ with `runtime error: MATHCK
<signed|unsigned> overflow in <SUCC|PRED|ABS|SQR> at line L column C
(operand=…)` (the column is the builtin name's), after flushing stdout and
evaluating the argument once, and wrap under MATHCK-. REAL ABS/SQR are
unchanged.
MATHCK- O0 IR has no overflow intrinsic, and the MATHCK+ program with its
snapshots stripped (a legacy AST) wraps when linked. CHAR, BOOLEAN and
enumeration SUCC/PRED are RANGECK's under either MATHCK setting: stepping
past the type's last or first value fails with the subrange diagnostic
(`value 3 is outside subrange 0..2`). The result has the argument's type,
so a subrange variable or designator argument (or a nested SUCC/PRED of one)
is checked against its declared bounds at the call under RANGECK+, before
any store; a subrange at its host's extreme fails MATHCK's base overflow
first. A user routine named
SUCC/PRED/SQR is an ordinary call. Fully constant SUCC/PRED/ABS/SQR must
fit its type (`WRITELN(SUCC(M))` with `M = 32767`, `WRITELN(ABS(N))` and
`WRITELN(SQR(200))` are rejected, as is `SQR(3037000500)` beyond INTEGER64;
`j := SUCC(M)` and `j := SQR(200)` into INTEGER32 are 32768 and 40000).
`SADDOK`/`SMULOK`/`UADDOK`/`UMULOK` must print the exact "fits" flag and
the wrapped 16-bit C for boundary pairs under both settings, both dialects,
O0–O3, both undeclared (inline; the IR calls neither the overflow failure
nor the library) and declared `EXTERN` as in the manual (linked from
libpascalrt). Designator operands and C, a user routine of the same name, and
rejected misuse (argument count, C not a variable or of the wrong type,
REAL operand) are covered too. A subrange variable or record field as C is a
typechecker type mismatch for all four (VAR needs the identical type), never
a codegen abort. Builtins the
[builtin classification](../docs/dialect_notes.md#mathck-builtin-classification) places outside MATHCK (ORD, WRD,
ODD, HIBYTE, LOBYTE, BYWORD, FLOAT) must print their defined results at
INTEGER/WORD extremes under MATHCK+ with no overflow call in the IR.
The unchecked CHR and CONCAT capacity gaps are documented there, not pinned
as results.

The cases are fixtures under `fixtures/mathck/builtin_*`, with expected
values from exact arithmetic written beside each row:

- `builtin_<type>_{ok,wrap,fail}`: per-type results that fit, wrapping, and
  traps (one stdin-selected case per trap, transcript in `.expected`).
- `builtin_domain_*`: RANGECK domain programs, with the failing statements
  and messages as a template plus table.
- `builtin_shadow`, `builtin_okfn*` and `builtin_nocheck`: shadowing, the
  SADDOK family and the no-check builtins.
- `builtin_constants*`: constant rejections (template plus table) and the
  valid constants program.

The suite runs its units in parallel and checks declared totals: 496
runtime cells, 10 MATHCK- IR, 10 snapshot and 40 legacy-AST cells, 26
constant cells, and 10 IR/rejection checks. Rejections must have the exact
three-line stderr, empty stdout and no executable.

### MATHCK mixed widths

`./tests/mathck_mixed_width.sh` (also in `make test-native`) covers operands
of different widths in the same family, extended dialect, O0–O3. For every
ordered width pair (8/16/32/64, signed and unsigned) and `+ - * DIV MOD`,
sample extremes whose exact result fits the *wider* type print it under both
settings, even when it exceeds the narrower one; results past the wider type
fail under MATHCK+ with the located diagnostic (operands shown at their own
values) and wrap at the wider width under MATHCK-. `INTEGER32 * INTEGER` is
pinned by name (`100000 * 20000` is 2000000000; `2147483647 * 2` fails). A
nonconstant INTEGER-family/WORD-family mixture (G24) is rejected with
`Mixed INTEGER-family and WORD-family operands need an explicit conversion
(e.g. WRD) in <op>` and no IR, for every signed/unsigned width pair, both
operand orders, all five operators and both settings (vintage 16/16 too).
Constants keep their adaptation: `w + (-1)` is unsigned WORD arithmetic
(wrapping to 4 under MATHCK-), `a + 40000` is INTEGER32, `w + WRD(i)` is the
explicit route; `i + 40000` (a WORD constant that does not fit INTEGER) is
rejected.

The full Cartesian matrix is checked in: for each of the 24 ordered pairs
there are `fixtures/mathck/mixed_<left>_<right>_{ok,wrap,fail}`. Their
headers list the sample values, and their `.out`/`.expected` hold exact or
wrapped results. In each pair's fail program, stdin selects one failing row
per operator, run at O0/O2. The other fixtures are
`mixed_named[_fail]`, the `mixed_admission.pas`/`.err` template and the
`mixed_constants.pas`/`.cases` template plus table. Together the pair
fixtures are about 480 KB (7,776 rows), the cost of keeping the matrix
explicit. The suite runs one unit per pair, admission partner and so on in
parallel, with declared totals: 192 fit, 96 wrap, 156 trap and 8 named
cells; 340 G24 rejections (exact stderr, no IR); 7 constants.

### MATHCK VECTOR lanes

`./tests/mathck_vector.sh` (also in `make test-native`) covers integer VECTOR
arithmetic for every element type (8/16/32/64-bit, signed and unsigned),
extended dialect, O0–O3. Boundary lanes that fit print exactly under both
settings. A lane `+ - *` or negation past the element range fails under
MATHCK+ with the scalar located diagnostic naming the lowest failing lane's
operands (a later lane overflows too), after the flushed prefix, and wraps
under MATHCK-. A zero DIV/MOD lane fails with the zero-divisor diagnostic
under either setting; signed MIN DIV -1 is MIN under MATHCK- and an overflow
under MATHCK+, MIN MOD -1 is 0. VSUM/VPROD print exact fitting folds, fail
under MATHCK+ at the first step past the range (`overflow in VSUM ...
(left=<partial>, right=<lane>)`), and wrap under MATHCK-. The MATHCK- O0 IR
keeps the vector `add`/`sub`/`mul` and `llvm.vector.reduce.add` with no
overflow intrinsic, and has no vector `sdiv`/`srem` (8 per-lane
`pas_math_zero` guards).

The fixtures are in `fixtures/mathck`, per element type:
`vector_<type>_ok.pas/.out` (the suite prepends either setting; same output)
and `vector_<type>_cases.pas`, one case per stdin value, each preceded by a
comment giving its derivation, with exact transcripts
`vector_<type>_checked.expected` (MATHCK+) and `_unchecked.expected`
(MATHCK-); plus `vector_ir.pas`. The suite runs one unit per type and setting
in parallel, with declared totals: 64 fit cells, 576 case cells and 1 IR
check.

### TRUNC/ROUND range (G26)

`./tests/trunc_round_range.sh` (also in `make test-native`) checks the
always-on TRUNC/ROUND INTEGER range check, both dialects, under
`{$MATHCK+}` and `{$MATHCK-}`, O0–O3: extreme valid results and ROUND's
half-away ties print exactly; `32768`/`-32769` (TRUNC), `32767.5`/`-32768.5`
(ROUND), `±1.0E300` and NaN fail with `runtime error: <TRUNC|ROUND> result
out of INTEGER range at line L column C (value=V)` after the flushed prefix;
a REAL32 argument is widened and checked. O0 IR reaches `fptosi` only in
`conv.ok`. A CPU DEVICE kernel fails the same way through LAUNCH; NVPTX IR
uses `llvm.fptosi.sat.i16.f64` with no plain `fptosi` and no host call.

Fixtures are under `fixtures/mathck/`: `trunc_round_valid.pas/.out`; the
`trunc_round_invalid.pas` template with one row per out-of-range call and
its exact diagnostic in `trunc_round_invalid.cases`;
`trunc_round_real32.pas/.err`; `trunc_round_device/` (interface,
implementation, host template and expectations); and `trunc_round_ir.pas`.
The directive is prepended to each program. Units run in parallel with
declared cell totals: 16 fit, 128 out of range, 8 REAL32, 4 CPU DEVICE, 2
NVPTX, 1 IR.

### MATHCK in DEVICE code

`./tests/mathck_device.sh` (also in `make test-native`) compiles NVPTX DEVICE
modules (`--device-triple nvptx64-nvidia-cuda -S`; no GPU needed): every
operation MATHCK+ would check (`+ - *`, DIV, MOD, unary `-`, SUCC, PRED, ABS,
SQR at INTEGER/INTEGER32/WORD, and an operation on enum constants) must fail
with exactly `MATHCK unsupported boundary: DEVICE arithmetic at line L column
C` and leave no IR; the MATHCK- twins compile with no overflow intrinsic or
`pas_math` call (DIV/MOD keep the mandatory-safety rejection, also with no
IR); constant folds, WORD ABS, REAL arithmetic, TRUNC and ORD are not
boundaries; a per-statement `{$MATHCK-}` opts out only its own operation.
A CPU DEVICE kernel launched from host code traps with the host diagnostic
under MATHCK+ and wraps under MATHCK- (O0/O2). Fixtures in
`tests/fixtures/mathck`: the module templates `device_module.pas` and
`device_enum.pas`; `device_nvptx.expected`, one record per compile (template,
setting and statement, then exit status, whether IR was written and is free
of checks, and exact stderr), which also drives the run; and
`device_bump/` (CPU unit, host and expected output). Declared totals: 18
rejected and 20 compiled NVPTX cells, 4 CPU cells.

### MATHCK address arithmetic boundary

`./tests/mathck_address_arith.sh` (also in `make test-native`): `^CHAR` +
WORD offsets 40000 and 32768 (either operand order) and ADRMEM + 40000 read
the right element under both settings at O0–O3; the MATHCK+ O0 IR for
`p + n` and `p + (n - 1)` has two non-inbounds GEPs and exactly one overflow
intrinsic (the offset's `-`); `p - 1`, `p * 2`, `p DIV 2`, `2 - p` and
`p + 1.5` are rejected by the typechecker with an exact message and no IR
written; a CINT returned by C `abs` and incremented in Pascal traps under
MATHCK+ and wraps under MATHCK-. Fixtures in `tests/fixtures/mathck`:
`address_word_offset.pas/.out`, `address_c_value.pas` with `_checked.out/.err`
and `_unchecked.out` (the setting is prepended), and `address_gep.pas`, whose
last statement the suite swaps for each rejected operator
(`address_reject.err`). Declared totals: 8 offset, 8 `[C]`, 1 IR, 5 rejection
cells.

### MATHCK diagnostics

`./tests/mathck_diagnostics.sh` (also in `make test-native`) runs one failing
program per MATHCK runtime class at O0/O2: signed and unsigned overflow in a
binary operator, unary minus, `SUCC` and `VSUM`, and signed and unsigned
division by zero. Each prints the `prefix` line, then exactly one
`runtime error: MATHCK <class> in <op> at line L column C (...)` line at the
operator or function-name token. Zero divisors fail under MATHCK- too, and the
overflow cases run to completion there. RANGECK store and SUCC/PRED domain
failures, INDEXCK bounds, INITCK reads and TRUNC failures are run beside them
and must keep their own texts, never the MATHCK stem. RANGECK and INDEXCK
messages are still unlocated; that is RANGECK/INDEXCK work
([contract](../docs/dialect_notes.md#mathck-runtime-diagnostics)).

The fixtures are in `fixtures/mathck`. `diag.pas` holds one failing statement
per stdin case (cases 0–6 MATHCK, 7–10 the other checks), and the suite
prepends either setting. `diag_checked.expected` and `diag_unchecked.expected`
are its exact transcripts, line and column included, so any accidental
renumbering of the source fails. `diag_initck.pas/.err` covers the INITCK
case. The suite also routes every failure: stderr is one line, it matches the
full MATHCK stem for a MATHCK case and never contains `MATHCK` otherwise.
Declared totals: 28 MATHCK, 8 other and 2 INITCK cells.

### MATHCK on/off twins

`./tests/mathck_twins.sh` (also in `make test-native`) checks that MATHCK
changes nothing for a program that never overflows. Every single-file fixture
under `tests/golden`, `tests/integration` and `tests/dialect` is built and run
with `{$MATHCK+}` and with `{$MATHCK-}` written in front of its first line
(line numbers do not move), at O0 and O2: compile status and diagnostics,
exit code, stdout and stderr must be identical. A fixture whose MATHCK+ run
reports a MATHCK error would be counted as overflowing and not compared (its
disabled twin wraps as the contract defines; the suites above pin that);
currently there are none. Link failures are compared by outcome only (the
driver does not link `-lm`, so three fixtures that call libm fail to link at
O0 under either setting). `fixtures/mathck/twin_extended.pas` adds what the
corpus lacks: every extended width, the scoped builtins, the SADDOK family,
VECTOR lanes and reductions and FOR loops ending at each type's maximum, with
results on each type's minimum and maximum; it must print
`twin_extended.out` under both settings at O0-O3. The 16-bit twin
`fixtures/mathck/twin_arith.pas` runs in `mathck_scalar.sh`. The suite runs
16 cells at a time in its own work directory, gives each run an empty
working directory, compares the outcome files byte for byte, and fails if
any directory yields no fixture or any cell leaves no result. Disabled
twins of *overflowing* programs run only in the suites that pin the defined
MATHCK- wrap (`mathck_scalar`, `mathck_builtins`, `mathck_vector`,
`mathck_mixed_width`, `mathck_diagnostics`, `mathck_address_arith`'s `[C]`
value, `mathck_device`'s CPU kernel) or the always-defined DIV/MOD results
(`mathck_divmod_safety`, baseline G8); each asserts the exact defined
result, never output from an undefined path.

### MATHCK boundary values

`./tests/mathck_boundary_values.sh` (also in `make test-native`) runs
`fixtures/mathck/boundary_values.pas` under MATHCK+ and MATHCK- in both
dialects at O0-O3 and requires `boundary_values.out` exactly. It produces
32767, -32768, 0 and 65535 through every checked 16-bit operation and the
edge results `-32767 - 1`, `-16384 * 2`, `PRED(-32767)`, `-32767 + (-1)`,
`MIN MOD -1`, `-7 DIV 2`, `MIN DIV 1`, `ABS(-32767)` and their WORD
counterparts, from variables and again as folded constants. -32768 is
ordinary data, so none of these may trap. At O0 the MATHCK+ IR must contain
one overflow failure block for each of the 44 operations on variables and
the MATHCK- IR none; both keep the 12 zero-divisor blocks. In a constant, a
sign applies to the whole term: the literal `-16384 * 2` is `-(16384 * 2)`
and is rejected because 16384 * 2 does not fit INTEGER, so the fixture
writes `(-16384) * 2`.

### MATHCK optimization

`./tests/mathck_optimization.sh` (also in `make test-native`) checks that
optimization never weakens the contract. `fixtures/mathck/fold.pas` emits 9
checks at O0. At O1-O3 its object keeps exactly the 5 that LLVM cannot bound
(accumulations and operations on a value read at run time). The 4 operations
bounded by constant FOR limits fold away, and the output is exact at O0-O3.
The same loop ending at 32767 still traps at the located `+` at every level.
For INTEGER8, INTEGER, WORD32 and INTEGER64 lanes, the O0 IR of a MATHCK+
VECTOR `+ - *` and negation must use one vector overflow intrinsic and one
`llvm.vector.reduce.or` branch per operation. The lane-by-lane failure path
appears only behind that branch. `mathck_vector.sh` pins the lowest-lane
diagnostics. The relocation count (`R_X86_64_PLT32 pas_math_overflow` in
`objdump -dr` output) is x86-64 specific. Fixtures: `fold.pas/.out` (stdin
`3`), `fold_bound.err` (the located trap of the loop edited to end at 32767)
and `vector_shape.pas` (an `{ELEM}` template). Declared totals: 4 fold, 4
bound and 4 vector cells.

## Host descriptor contracts

- [Transport and boundary probes](#descriptor-transport-and-boundary-probes)
- [NEW and index probes](#descriptor-new-and-index-probes)
- [Host ABI contract](../docs/dialect_notes.md#host-super-array-descriptor-abi-native)

### Descriptor transport and boundary probes

```sh
make test-descriptor-contract
# With current driver, runtime and bin/ stages already installed:
bash tests/descriptor_contract.sh
```

The Make target installs rebuilt stages and is included in `make test-native`.
The script reports failures and exits nonzero on any failure; there are no XFAILs
or expected-red success mode. Negative fixtures compile only (`-S`): undefined
EXTERN symbols cannot substitute for compiler rejection, and invalid raw pointers
or DEVICE launches are not executed. Exact new compile diagnostic wording is not
pinned: rejections require boundary-related diagnostics, not parser/name errors.

Inputs below are under `tests/descriptor/` unless otherwise named:

| Input / assertion family | Coverage |
| --- | --- |
| `transport.pas` / `.out` | Two allocation sizes at lower 2, variable/type aliases retain bounds after replacement, selected record/array slots, reads/writes, value/VAR (including selected actuals), pointer/record results, once-only calls/indexes, NIL assignment/arguments/equality; each allocation freed once. IR pins globals/aggregate slots, whole load/store and NEW/NIL publication, two-piece value/result and VAR-slot ABI, matching calls, no pre-data lookup/free. |
| `layout.pas` / `.out` | Descriptor and one-field record size 16, two-element descriptor array size 32. |
| `aggregate_abi.pas` | 32-byte descriptor pair uses SysV MEMORY/byval and sret, matching call attributes; sret pattern accepts preceding required `noalias`. |
| `register_budget.pas` / `.out` | After five GP arguments a descriptor rolls back wholly to byval, leaving a GP register for the trailing scalar; hidden sret consumes a GP register. RETURN does not append an epilogue after a terminated block. |
| `tests/integration/descriptor_units.*` | Separately compiled unit/program agree on exported globals, native value/result and selected VAR-slot ABI, not merely an in-module match. |
| `tests/golden/descriptor_unsafe*.pas` | Explicit import/export bounds and side-effect counts, selected UPPER of import, equality-by-data with differing upper, NIL raw printing, exact native free base and builtin shadowing. Compiler warnings checked separately from stdout, no ownership inference. |
| `tests/golden/descriptor_word_domain.pas`, `tests/golden/descriptor_ordinal_domains.pas` | WORD/CHAR/BOOLEAN/enum domains, full-width bounds and unsigned element offsets. |
| `unsafe_failures.pas` | Exact nonreturning runtime diagnostics before sentinel output under INDEXCK-: lower mismatch, WORD64 overflow, NIL, misalignment, upper below lower/outside domain. `tests/super_import_runtime.c` independently tests valid metadata, byte-span/address overflow and wide unsigned bounds without dereferencing addresses. |
| `reject_*.pas` | Implicit CPTR/thin/different-lower/nominal conversions; arithmetic/RETYPE/numeric I/O/slot ADR; pointer/aggregate-result argument mismatches; recursive C value/VAR/result/variadic/aggregate and known typed address paths; LAUNCH/DEVCOPY; invalid unsafe type/raw/bounds; deferred borrowed formals. |
| `device_thin.pas`, `device_interface_thin.pas` | Thin host/CPU-device/NVPTX DEVICE parameters and spliced interface storage after host-state restoration. These compile/IR probes do not require a GPU execution claim. |
| `foreign_recursive_thin.pas`, `reject_device_host_abi.pas`, `device_host_raw_interface.pas` | Ordinary recursive thin C signatures remain accepted; imported host descriptors rejected in DEVICE; opaque raw-only APIs survive a private unused host descriptor type. |
| `tests/dialect/vintage_unsafe_conversion.pas` | Unsafe syntax is extended-only. |

Runtime goldens are explicitly passed to `tests/run.sh`; automatic discovery does
not collect this directory's compile-only inputs. `DESCRIPTOR_DRIVER` selects an
alternate IR compiler only: runtime goldens retain the normal native runner driver.
The suite requires the C compiler/runtime archive for independent import tests.
Expectations pin descriptor layout, not the old thin-pointer representation;
implementation chronology and old red transcripts are not the current contract.

### Descriptor NEW and index probes

`make test-super-new` / `tests/super_new_contract.sh` (also in `make test-native`)
checks:

- Two valid and ten failing independent runtime arithmetic/allocation cases.
- Six selected-slot failure cases with test-only malloc/abort/free linker wrappers,
  exact diagnostics and once-only selection/bound counts; bound-expression side
  effects are not rolled back. No production allocator test hook.
- Huge source byte-size overflow under INDEXCK-, wide strides, whole publication
  IR, successful rebinding/alias retention, aligned vectors and exact free bases.
- `tests/descriptor/reject_new_*.pas`: overflowing static layouts, unsupported
  record offsets and over-alignment; huge allocations are never executed.

`tests/golden/indexck_super_*` plus descriptor-upper probes in
`tests/indexck_guard_ir.sh` cover endpoints, below/above, wide unsigned/negative
indexes, executed/dead constant bad indexes, once-only evaluation and per-slot
actual uppers. `indexck_super_nil_*` covers NIL load/store/selected record fields;
IR probes pin snapshots and guard-free disabled super subscripts. Index side-effect
ordering before NIL failure is deliberately not pinned down. Borrowed views and
temporal safety remain unsupported; the suite never executes invalid unchecked
scalar accesses. Related `tests/indexck_metadata.sh`, `bound_expression_*` goldens
and `make test-driver` preserve bounds evaluation and driver routing. Native
checklit/depth/stage/AST suites are broader gates, not substitutes for these probes.

## Opt-in overhead measurements

- [Reproduction and interpretation](#reproduction-and-interpretation)
- [INITCK workloads and memory](#initck-workloads-and-memory)
- [MATHCK workloads and optimization](#mathck-workloads-and-optimization)
- [Retained measurement snapshots](#retained-measurement-snapshots)

### Reproduction and interpretation

From the repository root, build the current driver, runtime and stages first:

```sh
make -j16 driver bootstrap
python3 tests/initck_overhead.py > build/initck-overhead.json
python3 tests/mathck_overhead.py > build/mathck-overhead.json
```

Both tools require Python 3, clang, GNU `size` and `/usr/bin/time`, plus the
normal compiler prerequisites. They use Linux `/proc/cpuinfo`; the INITCK
allocation probe also needs linker `--wrap=calloc`/`--wrap=free` support.
They are deliberately outside `make test-native`: timings are observations,
not correctness gates or release thresholds. Reports under `build/` are
persistent user-selected outputs, not scratch; a clean bootstrap deletes
`build/`, so preserve desired reports first. Temporary binaries/IR use the
[owned workspace contract](../docs/temporary_files.md).

Each initialized, non-overflowing fixture is compiled on/off at O0/O2, with
identical input, loop counts and other checking flags. Every invocation must
exit successfully with exact stdout and empty stderr; no unchecked
uninitialized data is executed. MATHCK also checks that off-mode IR has no
overflow intrinsics. Each binary has one untimed warmup and seven samples by
default, alternating off/on and on/off to reduce order bias. `--repeats N`
changes the sample count (minimum 3); use 3 for a smoke run, not a comparison
claim. JSON records revision, platform, CPU, clang, raw times/RSS and medians.

Run on an otherwise idle host. Wall times include process startup and the GNU
time launcher (roughly 1–2 ms in the retained MATHCK run), not compilation.
The tools do not pin CPUs or control frequency. Ratios near the startup floor
are not per-check costs; use absolute times and controlled-host repetitions.
GNU `size` text includes linked runtime/readonly sections, not just Pascal
routines; JSON also records data/BSS, ELF and IR bytes. ELF alignment can hide
small changes. MATHCK IR failure-call/intrinsic/vector-op counts describe
codegen's unoptimized `-S` output, not post-LLVM checks remaining in an object.
RSS includes runtime, allocator and page effects: no on/off separation is not
proof of zero instrumentation memory cost.

### INITCK workloads and memory

`initck_overhead.py` owns the three `fixtures/initck_bench_*.pas` workloads,
all in the vintage dialect, with input `0`:

| Workload | Work / exact stdout |
| --- | --- |
| Scalar | 60 million bounded updates after input / `0` |
| Aggregate/call | 30 million VAR updates and two whole-record copies per update, two-leaf shadow transport / `0:7` |
| Heap | 30,000 SUPER ARRAY rows of 64 INTEGERs, twenty full write/read passes (38.4 million writes and reads each), then DISPOSE / `1` |

**Off is not uninstrumented:** both modes allocate and propagate initialization
state. The comparison measures enabled reads together with taint collection,
helper arguments and optimizer decisions, not isolated branch cost or total
instrumentation versus an older compiler. Successful checked consumers can
establish initialized state while unchecked copies propagate unknown state;
an on-mode speedup does not show that checking generally improves performance.
A workload regression is not permission to weaken strict copies or alias-state
transport.

`tests/initck_bench_memory.c` measures requested calloc bytes from the real
heap registry in `runtime/build/libpascalrt.a` using test-only linker wrappers.
For 1,920,000 logical leaves, the retained run measured 3,840,000 Pascal data
bytes, 1,920,000 shadow bytes and 2,048 retained registry bytes: 1,922,048 total/
peak registry-plus-shadow bytes. The shadow is 50% of this INTEGER payload;
DISPOSE frees it but retains the registry table. This is requested allocation,
not RSS, and excludes allocator headers, fragmentation, stack/TLS metadata,
scratch/released lookups and registry growth across many allocations. Ratios
vary with leaf type (BOOLEAN/CHAR versus pointers/descriptors); this is not a
whole-program memory estimate. Baseline median RSS was about 1928–1932 KiB for
scalar/aggregate and 7288–7292 KiB for heap, with little on/off separation
because both modes own shadows; small stack shadows cannot be isolated by RSS.

### MATHCK workloads and optimization

`mathck_overhead.py` owns `fixtures/mathck/bench_*.pas`, with input `1`:

| Workload | Dialect | Work / exact stdout |
| --- | --- | --- |
| Scalar | vintage | 20 million `k := k + a[i] * 2 - a[i - 1]` on 1024 INTEGERs, one negation per row / `4665` |
| Builtins | vintage | 20 million rows of SQR, ABS and PRED in a subscript / `-8915` |
| Wide | extended | 20 million INTEGER32 multiply-accumulates into an INTEGER64 total / `6594377559292` |
| Vector | extended | 20 million steps of an 8-lane INTEGER32 recurrence `p := p + q * c; q := q - p` / `28 -28` |

Each stdout listed above ends with a newline. **MATHCK- is an unchecked
wrapping comparator for overflow**, unlike INITCK-off; mandatory zero-divisor
checks stay in both builds. O2 scalar/builtin ratios can largely reflect lost
vectorization/reassociation: unprovable per-operation overflow branches limit
LLVM transformations while unchecked loops approach the startup floor. SQR,
ABS and PRED introduce checks, including PRED in the subscript. The retained
runs had about 1.9 MiB RSS with no on/off separation; MATHCK does not keep
per-value shadow metadata.

Current checked VECTOR `+ - *`/negation uses one vector overflow intrinsic and
an OR-reduction branch, then a cold lane-by-lane path preserving the lowest
failing lane's operands and preventing result publication. Unchecked mode
keeps SIMD operations. DIV/MOD remains lane-by-lane to avoid LLVM undefined
behavior at a zero lane. The cold path increases text and still contributes
failure calls to the IR count; counts alone do not measure hot-path cost.
[Optimization regressions](#mathck-optimization) pin proven-safe checks folding
at O1–O3 and unprovable checks remaining. No compiler subrange facts are added:
RANGECK-off, uninitialized or variant-record values can violate declared bounds,
so assuming those bounds could turn an intended failure into undefined behavior.
`{$MATHCK-}` around a proven-hot kernel is the explicit overflow opt-out, not
permission to drop mandatory safety checks.

### Retained measurement snapshots

The benchmark maintainers (owners of the corresponding Python tool, fixtures
and memory probe) retain these JSON files for reproducible raw samples,
environment/size inspection and historical comparisons, not expected-output
oracles or timing thresholds. Inspect their `revision`/environment fields
before comparing; refresh intentionally alongside benchmark-method changes,
not by overwriting them with a routine smoke run.

| Snapshot (recorded date) | Purpose / concise observation |
| --- | --- |
| [INITCK baseline](../docs/initck-overhead-baseline.json) (2026-10-02) | Before metadata optimization; O2 aggregate/call on/off 1.700, text +3.1%; per-leaf shadow cost motivates investigation. |
| [MATHCK baseline](../docs/mathck-overhead-baseline.json) (2026-10-03) | Before whole-vector checks; VECTOR on/off 9.94 at O0 and 3.54 at O2, text +68.1%/+20.2%. |
| [MATHCK whole-vector run](../docs/mathck-overhead-optimized.json) (2026-10-03) | Same host/method; VECTOR on/off 2.21/1.82, text +71.9%/+21.3%; scalar/builtin/wide effectively unchanged. |

These retained runs used Linux x86-64, Ryzen 7 5800X, clang 21.1.8, seven
samples and no CPU pinning/frequency control. They do not describe current
performance on every host. Any optimization must rerun correctness suites and
measurements without weakening checks; proven-safe guard elimination is a
separate task. Broader claims need application, allocation-heavy, recursive
and external-boundary workloads, a genuinely uninstrumented INITCK comparator,
and repeated controlled-host measurements.

## INITCK support boundary

`./tests/initck_definite.sh` (also in `make test-native`) tests compiler-owned
scalar-local definite-initialization proofs. O0 IR counts pin removed guards
for direct assignments, known unchecked producers, BOOLEAN/CHAR locals and
both-arm IF joins, while retaining shadow slots/stores and output-call guards.
Both dialects at O0/O1/O2/O3 require exact initialized output and runtime failure
before derived output for a missing branch, GOTO bypass, zero-iteration loop, unchecked
unknown copy, and function-call mutation through VAR. Each unknown read retains
a metadata guard before its native load; disabled bad twins are compile-only.
The suite owns `fixtures/initck_definite_fail.pas` (OneBranch) and the four
`fixtures/initck_definite_fail_{goto_skip,zero_loop,unchecked_copy,call_effect}.pas`
variants. These retain the same declarations and source line layout, changing
only the final probe invocation; keep them synchronized when maintaining the
shared cases. The original OneBranch fixture also supplies the O0 structural
IR oracle for all five routines. These are not runnable golden tests. Validate
changes with `./scripts/test-env.sh ./tests/initck_definite.sh`.
The pass is conservative: calls, loops, selected destinations and unknown syntax
kill facts, GOTO/labels disable it, and aggregate/heap/formal/result guards stay.

`./tests/initck_validation.sh` (also in `make test-native`) is a focused
release gate using persistent `fixtures/initck_validation_*.pas`.
The values fixture accepts INTEGER zero and `-32768`, FALSE, CHAR `CHR(0)`,
and NIL after both checked and unchecked writes. Record/array transfers, heap
referents, and scalar value arguments/formals/results also accept zero and
`-32768`, proving initializedness is not encoded by reserved data values.
Success output is identical with checking on/off; a checked unset value actual
must fail even when its callee ignores it, with one exact diagnostic and no
later output. Both dialects run at O0/O1/O2/O3. The mixed fixtures combine
partial records/array elements, unchecked state-preserving aggregate copies,
forwarded VAR writes, CONST and WITH aliases, value arguments and scalar
results, and INITCK/DEBUG/PUSH/POP regions. Reading an initialized leaf of a
partial record succeeds; filling its missing leaf through VAR permits a checked
whole-value call. A partial unchecked copy/value argument must still fail at a
callee's checked CONST-alias read of the missing leaf, after exact prefix output.
O0 IR places the metadata branch and
terminating failure before the first native load and the ignored-argument call.
Disabled twins have no failure calls; both disabled unset-read twins are compiled
to IR only, never linked or executed. The old metadata-only on/off identical-IR
oracle is replaced by O0 assertions for located guards on scalar/pointer reads,
whole-record copies, array elements, heap leaves, formals and results. Both
on/off twins must retain scalar/aggregate shadow slots, copy state propagation,
heap registration/lookup/retirement and result-state publication: disabling a
guard is not disabling producers. Legacy/missing-read-snapshot opt-outs in
`initck_contract.sh` still compare identical IR only where no checked read
remains. Runtime failure requires nonzero status, not a platform-specific abort
code.

`./tests/initck_abi.sh` (also in `make test-native`) verifies initialized
on/off twin output in both dialects at O0/O1/O2/O3. O0 IR pins every tested
Pascal definition and call: scalar, value/VAR/CONST descriptor transport,
register-coerced descriptor/record results, and byval/sret descriptor pairs.
It also pins separate `{ ptr, i64 }` storage, alignment and whole descriptor
loads/stores; runtime SIZEOF is 16/16/32 for descriptor/holder/pair. Checked
reads really emit guards; disabled twins do not. Descriptor/aggregate result
boundaries remain explicitly INITCK- in both twins: this verifies ABI and
initialized output compatibility, not unsupported result enforcement. The
broader `descriptor_contract.sh` retains global layout, register-budget,
foreign and DEVICE ABI coverage.

`./tests/initck_contract.sh` (also in `make test-native`) checks boolean
INITCK metadata in lexer tokens, parser ASTs, and typed ASTs. It covers
standalone toggles, DEBUG coupling and overrides, PUSH/POP, `$IF INITCK`, and
declaration-boundary snapshots. Enabling a directive alone is silent; enabled
unsupported consumers fail in codegen before IR publication. Public-driver
probes distinguish enabled guard IR from disabled IR. A warning-replacement
gate in both dialects at O0/O2 requires unsupported declarations and literal
writes to remain silent, even across repeated INITCK/DEBUG/PUSH/POP transitions.
Two unsupported enabled reads must produce exactly the first located boundary
error and no IR, not a directive warning or diagnostic flood; disabled twins
compile silently. The external-boundary matrix separately pins each reachable
remaining category and its location, including CPU and NVPTX DEVICE consumers.
The disabled uninitialized read is compiled only, never executed.

`./tests/initck_state.sh` (also in `make test-native`) tests scalar-local
shadow allocation/reset independently of enabled guards. Exact O0 IR asserts flag-independent host
INTEGER/BOOLEAN/CHAR shadow allocas and false prologue stores, excluding globals,
formals, other types, and CPU/NVPTX DEVICE locals. Test-only IR instrumentation
reads and poisons **metadata**, never uninitialized Pascal bytes, to verify fresh
and distinct recursive activations, nested/sibling scopes, and repeated calls at
O0/O2. The fixture also pins supported direct-assignment state stores.

`./tests/initck_scalar.sh` tests successful INTEGER/BOOLEAN/CHAR assignments,
zero and literal -32768, disabled producers, conditions, skipped writes, fresh
recursive activations, early returns, REPEAT read-before-write, DEBUG overrides
and nested PUSH/POP. Repeated early-return invocations exercise both bypassed
uninitialized storage (no read) and initialized loop paths; negative cases cover
untaken conditional/WHILE writers, a recursive early-return branch with fresh
unset storage, and guard re-enablement through POP and DEBUG. Positive programs
run with checking on/off in both dialects at O0/O2. A dedicated disabled-write
matrix covers all three scalar types declared under INITCK+, both taken branches,
unchecked initialized RHS/copies, repeated calls, and disabled overwrites after
checked reads, in both dialects at O0/O2. A skipped disabled writer must leave
state unset for the next enabled read. O0/O2 failures must emit
one exact INITCK error with local name and read-site line/column and no output
after the failed read. Parser/typed metadata checks pin a parenthesized read's
identifier coordinates; O0/O2 tests cover source-aware and name-only older-AST
failures. Direct runtime probes distinguish INITCK, existing SUPER NIL-pointer,
and bounds diagnostics (not a NILCK directive coverage claim). O0 IR checks place
state publication after the data store and the metadata branch/failure block
before each native load; disabled and legacy bad reads remain compile-only.
Boundary cases cover globals, REAL, enums/subranges, a REAL heap
referent, a dereferenced global pointer, an array with
REAL elements, a record with a REAL field, the address of a WITH-bound
field, a FILE OF REAL buffer, LSTRINGs, sets, WITH over an untracked record, a local mentioned
under a nested WITH whose target fields are not evident, enabled END/RETURN of a REAL
function, a builtin call consumer, and CPU DEVICE. Each enabled case rejects with one exact category
line and no published IR at O0/O2; its disabled counterpart must compile cleanly
but is never executed. Late, disabled and untaken escapes still exclude
storage for the whole routine (`ADR` of a local or formal is a release at its
evaluation instead: `initck_external.sh`). Actual enclosing-local captures remain a separate
native compiler limitation, not a supported alias case. Broader producer, alias,
result and representation enforcement remains outstanding.

`./tests/initck_producers.sh` (also in `make test-native`) covers scalar
producers beyond literal assignment. Unchecked copies, expressions, chains and
comparisons of unset tracked locals leave the destination unset (exact O0/O2
failure at the later checked read). Initialized copies and overwrites of a
tainted slot succeed in both dialects at O0/O2, and an O0 IR check pins the
state accumulator. Stdin READ/READLN of INTEGER/CHAR/BOOLEAN initializes only
its destinations. An O0 IR check pins the status-gated select for file READ,
because file error trapping cannot be enabled from Pascal source. FOR control
is covered for TO/DOWNTO, CHAR/BOOLEAN, BREAK/GOTO retention and zero
iterations. Reads after natural termination, after a zero-iteration loop, and
from an unchecked unset initial value fail exactly. FOR over a global or an
INTEGER32 control variable under INITCK+ compiles without a boundary error.

`./tests/initck_routines.sh` (also in `make test-native`) is the routine-boundary
preservation gate. A correctly initialized program passes 0, FALSE, CHR(0) and
`-32768` through value, VAR and CONST formals, recurses and nests, and calls
functions that never assign their result. Those return the retained native
zero/default bytes for INTEGER, BOOLEAN, CHAR, REAL, pointer, coerced-record and
sret-record results, which is the agreed INITCK-off behavior. Output must match
exactly in both dialects at O0/O2, unannotated and with INITCK+ at each enabled
read the current slice accepts. Every routine definition and Pascal call site is
pinned at O0 and must be identical in both variants, so instrumentation adds no
hidden parameters or result changes. The suite owns
`fixtures/initck_routines_{plain,checked}.pas`; maintain them together, preserving
INITCK-off at unassigned or unsupported/default returns. The plain fixture
retains the former expansion's spacing, including two spaces on blank line 35,
for byte equivalence. These are suite inputs, not runnable golden tests.
Validate changes with `./scripts/test-env.sh ./tests/initck_routines.sh`.
The same script covers value formals and tracked results. A fully checked program passes 0, FALSE, CHR(0) and `-32768`
through formals and results, nests calls, recurses with an early RETURN, and
hands unset actuals to callees that ignore or overwrite them, in both dialects
at O0/O2. Exact O0/O2 failures cover a checked unset actual at the caller, an
unchecked unset actual read in the callee or copied to a callee local, an
unassigned result at an enabled END or RETURN, an unchecked return tainting
the caller, a result assigned on one path only, a fresh recursive result, and
nested calls that must not cross argument states. An O0 IR check pins the side
channel: the callee copies and clears its slot before any call, the caller
publishes after evaluating all actuals, then resets the result flag, then
clears after the call, and untracked REAL formals get no slot. VAR/CONST coverage
is also exact, in both dialects at O0/O2. Callee writes initialize the caller's
locals, forwarding works, `swap(x, x)` shares one binding, and BOOLEAN/CHAR
formals are covered. A global binds a private initialized slot. An
address-escaped formal releases its caller's slot. A C-implemented plain EXTERN
that never clears its slot cannot disturb the next call. Exact failures cover
VAR and CONST reads of an unset caller local, an unchecked copy through CONST
into VAR, forwarding, and a callee that writes on one path only. An O0 IR check
shows that a tracked VAR actual publishes the caller's own state slot (a
global publishes nothing) and that the callee guards and writes through its
selected binding. Nested routines and WITH are also covered in both dialects at
O0/O2. Same-name formals and locals two levels deep leave the enclosing local
tracked. Locals are written and checked inside WITH bodies (single, multiple
and VAR-formal targets) while a same-name field shadows without touching the
local. Exact failures cover an unset local read inside a WITH body, a nested
routine's own unset local, and an enclosing local left unset by a nested
routine. The suite owns `fixtures/initck_routines_{withread,nestedread,nestedother}.pas`
for these three failures: retain body line 9 and nested declaration line 4,
which feed the exact diagnostic oracle. Do not run their unchecked bad twins.
An enabled captured read is the exact `global or captured storage`
boundary. With INITCK disabled, the pre-existing capture limitation still
rejects the program, and INITCK adds nothing to that error.

`./tests/initck_aggregates.sh` (also in `make test-native`) covers INITCK
aggregates: fixed ARRAYs and RECORDs of INTEGER/BOOLEAN/CHAR leaves, nested
arrays of records and records of arrays, CHAR-indexed arrays and dynamic
indices. Positive programs run in both dialects at O0/O2 with zero and
`-32768` values, disabled component writes, READ/READLN into components and
unchecked component copies. Exact O0/O2 failures show that one write never
initializes a neighbor (element, field, nested, dynamic, two-level and
computed-index cases), that each recursive activation starts unset, that an
unchecked unset component taints a scalar or component copy, that an index
with unset state taints the selected value, and that READ initializes only its
own destination. An out-of-range index reports the bounds error before INITCK,
and an O0 IR check orders bounds check, element-shadow GEP, metadata branch
and failure call before the native element load. Aggregate copies: a positive
program in both dialects at O0/O2 performs checked whole, element and
self-copies, an unchecked partial array copy that keeps per-leaf states, a
global round trip, a call result, and checked and transported value actuals.
Exact failures cover a checked partial source, unchecked partial, self and
element copies read later, a checked partial sub-aggregate source, a checked
partial value actual at the caller, an unchecked one failing at the callee's
own read, and an index with unset state unsetting the copy. An O0 IR check
orders the whole-shadow check before the source load and each leaf-state
transfer after its data store. Variant records: a positive program (both
dialects, O0/O2) checks a transfer with fixed fields plus one complete
alternative, a tag change that keeps the written alternative readable, an
empty alternative, element-wise checks of arrays of variant records (tagged
and tagless) and an unchecked copy keeping per-alternative states. Exact
failures cover reading another alternative's overlapping field (tagged and
tagless punning), a tag and an alternative not initializing each other, and
checked transfers with an incomplete alternative, an unset tag, or an array
element with no complete alternative. Aliases: a positive program (both
dialects, O0/O2) shares leaf, whole, sub-aggregate and forwarded VAR/CONST
bindings, runs WITH over a record, a selected element and a computed-index
element, binds a global privately and releases an escaped formal. Exact
failures cover a callee's checked read of an unset bound leaf, a callee
writing one element, a checked whole copy of a partially written VAR formal,
a CONST component read, and WITH writes leaving siblings unset (after the
WITH, inside it as `field y`, and through a selected sub-record). WITH-bound
names resolve to fields before routine locals: a tracked field wins over a
same-named REAL local, and an untracked LSTRING field is an exact boundary for
output and CONCAT. Representations: PACKED arrays and records are rejected by
codegen identically with INITCK on and off; LSTRING (element and `.LEN`),
STRING, SET, VECTOR and BOOLEAN-vector components, and a record holding an
LSTRING, are exact O0/O2 boundaries whose INITCK-disabled twins compile
cleanly. Single evaluation: a side-effecting index function is
called exactly once per designator across checked reads, writes, READ, VAR
bindings, WITH targets, both sides of an aggregate copy and an INDEXCK-
read (both dialects, O0/O2); failing INITCK and bounds checks follow exactly
one call; and an O0 IR check shows that without INDEXCK the element shadow
reuses the data GEP's own offset value. Boundary cases for
aggregates with untracked leaves, whole-aggregate uses and selected VAR
actuals are in `initck_scalar.sh`.

`./tests/initck_heap.sh` (also in `make test-native`) covers INITCK pointers
and heap storage. Pointer values: a positive program (both dialects, O0/O2,
INITCK+ wherever the slice supports it) initializes pointers by NEW, NEW
through a VAR formal and NEW of a record field, copies, compares against NIL
and each other, passes and returns them, and DISPOSEs them. Exact O0/O2
failures read an unset pointer in a comparison, at a dereference in an
assignment target (reported at the `^`), as a selected record field, in
DISPOSE (a local and an array element), after an unchecked copy, after NEW
on an untaken branch, in a callee after an unchecked value actual, and as an
unassigned pointer result. An O0 IR check orders NEW's pointer store before
its state publication and the pointer guard before the native pointer load.
Heap referents of ordinary NEW: a positive program (both dialects, O0/O2,
INITCK+ throughout) writes and reads record, scalar and array referents
including zero, FALSE and `-32768`, builds and walks a linked list, shares
state through a second pointer, initializes through WITH-bound fields and
VAR bindings, and copies whole heap sub-records and passes them by value; a
second program shows a disabled write and an unchecked partial heap copy
keeping per-leaf state. Exact O0/O2 failures: a fresh referent, a sibling
field, an unset heap pointer field at its `^`, a renewed referent, a read
through an aliasing pointer, array and scalar referents, a WITH-bound field,
a callee's VAR read, a checked whole copy, an unchecked partial copy read
later, and an unchecked heap read tainting a local. Releases (extended
dialect, O0/O2): C-allocated memory, and referents written by C after a
WITH-bound field's ADR, a pointer-to-ADRMEM conversion and an ADRMEM actual,
read checked without false positives; an executed `[C]` routine writes a
referent through its pointer argument. An O0 IR check orders allocation,
state registration, pointer publication, and lookup and guard before the
native load. SUPER ARRAY descriptors (extended dialect, O0/O2): a positive
program initializes descriptors by NEW, NEW through a VAR formal into a
record field, a function result and UNSAFESUPER, copies, compares and passes
them, and reads them by UPPER and UNSAFERAW. Exact failures read an unset
descriptor in UPPER (at its `^`), a comparison, DISPOSE, an element store,
after an unchecked copy, as a record field, in a callee and as an unassigned
result. An O0 IR check orders NEW's descriptor store before its state and the
descriptor guard before the descriptor load and UPPER's NIL check. Heap SUPER
ARRAY elements (extended, O0/O2): a positive program writes and reads INTEGER
elements from a negative lower bound (including `-32768`), record and pointer
elements, swaps elements through VAR formals, fills them in a callee through a
copied descriptor, binds one with WITH, and reads elements after VSTORE
released the allocation. Exact failures: a fresh element, a neighbor, a
sibling field, a renewed allocation, a read through an aliasing descriptor, a
callee's VAR read, a WITH-bound field and an unchecked element read tainting a
local. Elements exported with UNSAFERAW and written by C, and C memory
imported with UNSAFESUPER, read checked without false positives. An O0 IR
check orders `pas_super_new`, the `count * leaves` registration and the
descriptor publication, and the bounds check, per-element lookup and guard
before the native element load. DISPOSE: a NEW after DISPOSE fails as a fresh referent; C memory that
reuses a disposed address (glibc does) reads without a false positive, and
deleting the retirement call from the IR (a mutation check, run whenever the
address was reused) makes it fail; an O0 IR check orders the pointer guard,
pointer load, retirement and `free` for a pointer and a descriptor.
Nesting and aliases (extended, O0/O2): a recursive binary tree built and
summed with checked reads, a pointer to a pointer, a heap record holding a
SUPER ARRAY descriptor and an array of pointers, whole referents bound to
VAR and CONST formals and passed by value, a heap variant record written
through both alternatives, and a nested WITH over heap records (unchecked;
the released referent then reads checked without failing). Exact failures:
an unset pointer inside a referent at its `^`, an unset descriptor in a
referent, an unset element behind it, an unset pointer two levels deep, a
field a VAR callee did not write, a CONST callee's read, a partial value
actual, and an unwritten variant alternative and tag.
Allocation failure (`tests/initck_heap_publication.c`, linker-wrapped
malloc/calloc/abort, O0/O2): a failed ordinary NEW data allocation, its state
allocation, a failed SUPER ARRAY NEW data allocation, its state allocation,
and a failed registry-table growth each abort with their exact diagnostic
while both destinations and the old referents' state are unchanged and any
successful data allocation stays unregistered; an IR check places the
ordinary NEW failure branch before registration and publication.
`tests/initck_heap_runtime.c` unit-tests the registry (ranges, mismatched
counts, releases, retirement, reuse, growth with tombstones, scratch, and the
per-site fallback runs of `pas_initck_heap_at`/`pas_initck_heap_part_at`).
Exact boundaries: a global pointer dereferenced, a referent with a REAL field, a field read
inside a WITH whose body releases its referent, and a REAL SUPER ARRAY
element.

`./tests/initck_external.sh` (also in `make test-native`) covers INITCK at
external boundaries, linking generated IR with a C helper. C calls: a `[C]`
VAR/CONST binding initializes exactly the bound storage (a scalar, a whole
array, one element; a CONST binding of a written local) and nothing else
(exact failures for the sibling element and an unrelated local). Plain
EXTERNs implemented in C (no handshake acknowledgement) release their VAR
binding and a typed pointer's referent after the call and return an
initialized result; a Pascal routine C calls back during such a call ignores
the caller's published slots. Four IR mutations (no release, no referent
release, an unconditional tag match, no acknowledgement test) each turn the
positive program into its exact false positive. A separately compiled MODULE
behind plain EXTERN declarations acknowledges, so its unwritten VAR binding,
unset result and unwritten referent still fail exactly. An O0 IR check pins
the caller's tag/flag/release order, the `[C]` fill before the call and the
callee's tag comparison before its first slot load. Raw addresses (`raw`,
O0/O2): `fillc(ADR flags, ...)`, a write through a typed pointer converted
from `ADR x`, `ADR` of a VAR formal, an address-taken FOR control variable
written after natural exit, an address-taken pointer local, descriptors
passed by value and by VAR to a C plain EXTERN that writes their elements,
and a `[C]` ADRMEM result, all checked. Exact failures: a read before the
`ADR`, an untaken `ADR`, another local, an unset ADRMEM read and an unset
ADRMEM transported to a callee. Mutations removing the `ADR` release or the
descriptor release restore false positives; an IR twin without the `ADR`
keeps the FOR natural-exit unset. Files (`files`, O0/O2, INITCK+): REWRITE/
PUT/RESET/GET/EOF/EOLN/CLOSE/WRITELN on local and global files, `-32768` and
0 through a FILE OF INTEGER, a buffer written by a `[C]` VAR binding, a record
buffer written and copied whole, and a TEXT buffer read and consumed. Exact
failures: an unwritten buffer read and PUT, PUT after PUT, a partial record
buffer PUT and copied, and the buffer at EOF; an IR check places the state
beside the buffer and the PUT guard before the runtime's write. FILE OF REAL
is the `filereal` boundary in `initck_scalar.sh`. DEVICE: a CPU-device host
program (O0/O2, INITCK+) launches a kernel that writes a never-written NEW
referent and reads it back checked, and round-trips an array through
DEVALLOC/DEVCOPYTO/DEVCOPYFROM/DEVFREE; IR places the referent release
before `pas_dev_launch`. An enabled read in a CPU and an NVPTX DEVICE
compiland is exactly `DEVICE code` with no IR. The compile-only input is
`fixtures/initck_external_device_read.pas`, owned by this suite; it disables
INITCK after the read, before closing END. The distinct
`fixtures/initck_scalar_device_read.pas`, owned by `initck_scalar.sh`, leaves
INITCK enabled at END and has a compile-only disabled twin. Keep their line
layout stable: the external suite checks the read's line 11 coordinate.
Neither fixture is a runnable golden test. Run their owning suites through
`./scripts/test-env.sh ./tests/initck_external.sh` and
`./scripts/test-env.sh ./tests/initck_scalar.sh` when maintaining them.
Diagnostics (`bnd`, O0/O2):
every reachable boundary category gives its exact line with the consuming
token's location and no IR, and its INITCK-disabled twin compiles cleanly;
`selected storage` is defensive and documented as unreachable. Review
regressions (O0/O2): VAR aliases of two distinct released heap records and
of two distinct C cells keep separate state (`untracked`); a `[C]` VAR
binding, a pointer value handed to `[C]` and an `ADR` actual take effect at
the call, so a later actual reading the same storage fails exactly when it
is unset (`callorder`, `orderbad`); a `[C]` result and a Pascal result
through an untracked REAL formal stay initialized after an unchecked unset
actual (`argscope`); a checked main-body read of a program variable is the
`global or captured storage` boundary (`mainbnd`). The other
scripts' boundary loops compare categories with the location stripped.

INITCK scalar producer and calling-boundary matrix. Every rule has executed
positive and exact negative coverage at O0/O2 unless marked IR/compile-only.
Scripts: S = `initck_scalar.sh`, P = `initck_producers.sh`, R =
`initck_routines.sh`, X = `initck_external.sh`.

| Rule | Positive | Negative |
|---|---|---|
| Direct assignment, flag-independent | S good/disabled-writes | S expression/skipped/recursion |
| Unchecked copy carries source state | P copy-ok | P copy-bad (6 shapes) |
| READ/READLN destination (stdin) | P read-ok, formal-ok | P read-bad; file trap IR-only |
| FOR control; unset after natural exit | P for-ok, formal-ok | P for-bad (6), formal-bad (VAR) |
| Value formal receives actual state | R transport-ok | R formal, formalcopy, nested |
| Checked actual read at caller | R transport-ok | R actual; `[C]` actual in cinterop |
| Result: name assignment, RETURN/END | R transport-ok, sites-ok | R endresult/returnresult/partial/recursion, debugend/pushreturn |
| Unchecked return taints caller | R transport-ok | R taintresult |
| VAR/CONST share caller state | R var-ok, recvar-ok | R varread/constread/varcopy/forward/partial, recvar-bad |
| Untracked binding / escaped formal | R var-ok (global, zap) | n/a (assumed initialized) |
| Uninstrumented C caller/callee | R cinterop (mutation-checked) | R cinterop `[C]` actual |
| Nested redeclaration, WITH locals | R scope-ok | R withread/nestedread/nestedother |
| Captures, untracked results | n/a | R capture; S boundaries |
| `[C]` VAR/CONST binding, C-implemented EXTERN | X cwrite, modok | X sibling/other, modvar/modres/modptr, mutations |
| `ADR` release, ADRMEM values, descriptors to C | X raw | X before/untaken/other/adrmem/transport, mutations |
| File names, buffer fill/EOF/PUT, buffer writes | X files | X unwritten/put/putput/partialput/partialread/eof; S filereal |
| Host LAUNCH/device builtins; DEVICE compilands | X devhost | X devread (CPU, NVPTX); S device |
| Boundary categories and locations | n/a | X bnd (11 categories), devread |
| Legacy AST without return snapshots | R legacyret (no guard) | n/a (opt-out) |
| Signatures/defaults preserved | R plain/checked gate | n/a |

`tests/fixtures/initck_reads.pas` and the native `initck_read_check.pas` probe
also check independent `read_flags` snapshots on expression/designator nodes,
call and UPPER consumers, index and dereference selectors, assignment and WITH
targets, and transparent parentheses. Directives inside statements deliberately
make consumer flags differ from declaration, statement-entry, and later-token
flags. Parser and typed snapshots must match the exact oracle; codegen rejects
the resulting enabled unsupported reads. These are compile-only metadata tests, not initializedness
tests. Frozen historical AST comparisons ignore this new native metadata key;
the focused INITCK test checks it explicitly.

`tests/fixtures/initck_read_toggles.pas` adds exact, separate declaration and
read-site oracles for globals and routine locals declared under both INITCK
states. Repeated uses of each slot toggle within one statement; assignment,
condition, and call operands also differ from statement-entry flags. A directive
after an emitted assignment-target identifier changes the RHS snapshot, not the
target's. Both parser and typed ASTs are checked; codegen rejects the enabled
unsupported consumers. The uninitialized reads are never executed.

`tests/fixtures/initck_read_transitions.pas` extends the actual-read oracle to
DEBUG coupling/recoupling, explicit overrides in both directions, nested
PUSH/POP, both `$IF INITCK` branches, and nested skipped directives/includes.
Two active include fragments carry reads and flag changes back to their caller,
including a PUSH in one include restored by POP in the other. A skipped missing
include must not be opened. DEBUG after an emitted identifier changes only the
next consumer. Exact parser/typed snapshots and codegen boundary rejection are checked;
these fixtures remain compile-only and do not claim runtime protection.

The INITCK contract script also strips all or alternating `read_flags` from
parser and typed AST inputs to simulate legacy and mixed producers. Rechecking
must preserve absent and explicit snapshots independently, even with enabled
declaration/statement flags still present. Codegen accepts each input and emits
identical unchecked IR for these particular retained non-consuming snapshots.
Missing snapshots are a legacy unchecked opt-out,
never inferred enabled reads; no uninitialized probe is executed.

## Overview of Test Suites

### 1. Driver Contract Test Suite (`tests/driver.sh`)
- **Runner**: [`tests/driver.sh`](./driver.sh)
- **Description**: Checks the public driver CLI without a bootstrap build. The runner uses temporary stage programs to check option errors, missing sources and stages, failed stages and `clang`, literal source and output paths, default IR output, and multi-file linking.
- **Running**:
  ```bash
  make test-driver
  ```

### 2. Golden-File Test Suite (`tests/golden/`)
- **Runner**: [`tests/run.sh`](./run.sh)
- **Description**: Fast, end-to-end integration tests using the native driver binary (`bin/pascal1981-native`). Each test is compiled and executed, verifying exit codes, standard output, and standard error against expected golden files (`.out`, `.err`, `.exitcode`).
- **Running**:
  ```bash
  ./tests/run.sh
  ```
  To run with parallel worker jobs:
  ```bash
  ./tests/run.sh -j 4
  ```

### Completion-proxy conformance (retained)

Keep proxy conformance outside the first Python-harness migration. `make test`
includes `test-proxy`; `make test-native` builds the proxy tool but does not
run this target. Run `make test-proxy` or a focused wrapper through
`./scripts/test-env.sh ./tests/proxy/<name>.sh`. The canonical
[proxy suite guide](proxy/README.md) describes its fixtures and normalization
contract. Frozen reports came from the replaced Python **proxy**, not the
Python **compiler**; the old proxy implementation is no longer run.

| Retained Python component | Purpose / invocation | Maintenance responsibility |
| --- | --- | --- |
| `proxy/run_conformance.py` | `proxy/run.sh` calls it to orchestrate stub/proxy daemons and native raw-request replay, then calls it again with `--compare` for recorded-report equality. Calibration/response normalization remain Python. | Proxy protocol maintainers own normalization, daemon lifecycle, calibration and case membership. Preserve golden failures; `--record` is for an intentional contract change, not blessing current output. Keep native_temp for private diagnostic logs. |
| `proxy/stub_upstream.py` | Deterministic HTTP reply shapes and request-payload inspection; launched by conformance, `proxy/oneshot.sh`, and default `proxy/corpus_smoke.sh`. An explicit smoke `--base-url` bypasses the stub. | Proxy/client maintainers own scenario markers, malformed/error/timeout replies, effort calibration and payload capture. Retain deterministic local tests; a live model is not an equality oracle. |

The other `test-proxy` wrappers (`transforms_check.sh` and
`corpus_reference_check.sh`) are native checks and remain wired unchanged.
The [shared-support/wrapper audit](#shared-support-parity-and-wrapper-audit)
records private port-publication coverage and outstanding daemon-supervision
and case-uniqueness findings. Retention is not a claim that all paths are fully
hardened.

### 3. Parity Test Suite (`tests/parity/`) -- opt-in, retained
- **Status**: disabled. The native compiler is authoritative; the Python compiler (`pascal1981`) is an earlier implementation, not an oracle, and the native stages deliberately diverge from it (for example, parser/typechecker `read_flags` for INITCK), so many comparisons fail by design. `make test-reference-parity` only prints a notice unless `ENABLE_PYTHON_PARITY=1` is set. Do not add fixtures or treat failures as defects.
- **Scope decision**: retain all seven modules and `tests/support.py` outside
  the first migration. Complete removal requires a separate decision; these
  comparisons are not independent numeric oracles and do not define native
  correctness. Do not mechanically make native behavior match the reference.
- **Maintenance responsibility**: maintainers using this historical comparison
  own its optional prerequisites, known divergence/skip interpretation and
  selected native stage binaries. Keep `native_temp` imports in workspace
  clients; never delete shared support merely because an unrelated shell suite
  no longer uses Python. Neither `make test` nor `make test-native` invokes
  `test-reference-parity`.
- **Runner**: `pytest` (`PYTHON`, default `python3`, selects the Make runner;
  `PYTHONPATH=.` is supplied by Make). This opt-in target does not build native
  tools for you; use existing binaries or the modules' `NATIVE_*` overrides.
- **Description**: compares native compiler stages (`lexer`, `parser`, `typechecker`, `codegen`) with the Python implementation: AST equivalence, code generation, record layouts, deep recursion limits, and device/kernel launches.
- **Running** (manual comparison only):
  ```bash
  make test-reference-parity ENABLE_PYTHON_PARITY=1
  ```
- **Retained components** (all under `tests/parity/`):
  - `test_native_parity.py`: stage AST/rejection and linked-output comparisons.
  - `test_depth_limits.py`: reference depth guards/CLI and parsing self-hosting
    sources; it does not compare native depth constants.
  - `test_self_host_record_layout.py`: ten literal historical record snapshots
    through reference/optional-native pipelines against LLVM TargetData;
    not automatic discovery of current source records or a numeric oracle.
  - `test_native_device_units.py`: reference-front-end DEVICE roots lowered to NVPTX.
  - `test_native_device_orchestration.py`: reference-front-end CPU device orchestration.
  - `test_native_host_uses_device.py`: host USES/DEVICE interfaces and aliases.
  - `test_native_kernel_launch.py`: kernel attributes and host launch ABI/runtime.
  `tests/support.py` supplies capability/skip probes and reference parse,
  typecheck, project/link/run helpers; the direct parity importers are
  `test_native_parity.py` and `test_self_host_record_layout.py`. Its workspace
  import and transitive reference dependencies remain retained.
- **No `VECTOR` here.** The Python compiler has no `VECTOR [n] OF ...` construct, so any parity fixture using one diverges by construction (it rejects it). `VECTOR` behaviour is covered end-to-end by `tests/golden/` (runtime) and plain-`.pas` checklit fixtures (IR shape) instead. Separately, every file that `gen1` compiles must stay inside the bootstrap subset that `pasboot` translates, which leaves out `VECTOR` and much else; `make check-bootstrap-subset` enforces it. See [`docs/bootstrap_subset.md`](../docs/bootstrap_subset.md).

### 4. Checklit Directive Suite (`tests/checklit/)`
- **Runner**: [`tests/checklit.sh`](./checklit.sh)
- **Description**: Makes zero-Python assertions on emitted LLVM IR or PTX text. The runner supports required, forbidden, and counted substrings. It does not enforce check order.
- **Pascal fixture format**: Put directive comments in a `.pas` file. Use `{ CHECK: text }`, `{ CHECK-NOT: text }`, or `{ CHECK-COUNT: N text }`. Use `{ CHECK-ANY: text || alternative }` when LLVM versions use different text for the same contract. Use `{ CHECK-FLAGS: --opt val }` to add driver/codegen arguments for the compile (e.g. `--target-cpu x86-64-v3`, `--emit-ptx`, `--device-triple <triple>`). `{ CHECK-ENV: NAME=value }` still sets a codegen environment variable but is rarely needed now that those options are command-line.
- **Frozen AST format**: A `.check` file can use `{ CHECK-INPUT: path.json }`. The runner sends that typed AST to native codegen. Sources and frozen Python reference ASTs are in `tests/reference/codegen/`. A frozen AST is produced by the Python reference, so it can never contain `VECTOR` -- use a plain `.pas` checklit fixture for any `VECTOR` IR-shape assertion.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-codegen.sh`. Review all JSON changes before you commit them. Routine tests do not run this Python-based maintenance command.
- **Running**:
  ```bash
  ./tests/checklit.sh
  ```

### 5. Native Depth Test Suite (`tests/depth.sh`)

- **Runner**: [`tests/depth.sh`](./depth.sh)
- **Description**: Checks expression, statement, and type nesting boundaries in the native parser. It checks depth unwinding between sibling expressions. It also sends frozen oversized ASTs to the native typechecker and code generator. Bounded tests use a five-second timeout; parser and typechecker tests also use a 128 MiB address-space limit.
- **Artifact updates**: Run `PYTHONPATH=. ./scripts/update-reference-depth.py`. Review changes under `tests/reference/depth/` before you commit them. Routine tests do not run this maintenance command.
- **Running**:
  ```bash
  ./tests/depth.sh
  ```

### 6. Native JSON Comparator Suite (`tests/astcompare.sh`)

- **Runner**: [`tests/astcompare.sh`](./astcompare.sh)
- **Tool**: `bin/astcompare`
- **Description**: Checks structural JSON comparison without Python. Object keys are unordered, arrays are ordered, and `--ignore-key KEY` applies recursively. Mismatches report a JSON path. The suite also compares native parser and typechecker output with frozen Python-reference ASTs. Typed comparisons ignore the output-only `resolved_type` field.
- **Artifact updates**: Run `./scripts/update-reference-ast.sh`. Review the Pascal sources and JSON under `tests/reference/ast/` before you commit changes. Routine tests do not run this Python-based maintenance command.
- **Running**:
  ```bash
  ./tests/astcompare.sh
  ```

### 7. GPU Orchestration Suite (`tests/gpu_orchestration.sh`)

- **Runner**: [`tests/gpu_orchestration.sh`](./gpu_orchestration.sh)
- **Description**: Compiles and runs vector addition with the CUDA backend. The runner uses frozen typed ASTs from the independent Python front end. It checks each GPU and CUDA prerequisite. It prints one skip reason if a prerequisite is not available.
- **Artifact updates**: Run `./scripts/update-reference-gpu.sh`. Review the Pascal sources and typed ASTs under `tests/gpu/` before you commit changes.
- **Running**:
  ```bash
  make test-gpu
  ```

### 8. Pre-Commit Hook Test Suite (`tests/test_precommit_hook.sh`)

- **Runner**: [`tests/test_precommit_hook.sh`](./test_precommit_hook.sh)
- **Description**: Checks hook restaging, partial staging, tool errors, optional tools, and the executable file mode. Each behavior test uses an isolated Git repository. `beautify.sh` must leave an already formatted C file untouched, mtime included: every `runtime/*.c` is a prerequisite of the runtime archive and so of all four bootstrap generations, so rewriting unchanged files on each commit would force a full rebuild on the next `make`.
- **Requirements**: `git` and `indent`. The test of Python restaging also needs `isort` and `yapf`; without them, the runner skips that one test and names the missing tools. A formatter that is on `PATH` but does not run still fails the hook, by design.
- **Running**:
  ```bash
  ./tests/test_precommit_hook.sh
  ```

---

## Running the Routine Tests

Run the routine compiler and hook tests:

```bash
make test
```

This target does not require pytest. It does not run the (disabled) Python parity suite.
