# Retained Python test infrastructure

Which Python components the test suites still use, why they are kept, and what replacing each would have to preserve. The test suites themselves are described in
[tests/README.md](../../tests/README.md).

## Temporary-file isolation

See the canonical [temporary-file ownership contract](../temporary_files.md)
for harness workspace ownership, per-fixture/per-cell isolation, signal cleanup,
and the distinction between scratch data and persistent build reports. Keep
these rules together rather than duplicating them in individual suite guides.

### Retained Python temporary infrastructure

Keep `scripts/native_temp.py` and `tests/contract/temp_hygiene.py` during the Python
reduction. They enforce/check the ownership contract, not arithmetic oracles.
Moving their Python into another module is not a reduction; replacing either
requires its own security/cleanup equivalence gate, not a source translation.

| Component | Purpose and invocation | Maintenance responsibility |
| --- | --- | --- |
| `scripts/native_temp.py` | Imported before any scratch allocation; validates the root, owns one interpreter workspace, redirects `tempfile` and child `TMPDIR`, and registers owner-only exit/signal cleanup. Not a CLI. | Maintainers changing Python workspace clients must preserve import-before-allocation, PID ownership, cleanup registration under blocked signals, and default INT / HUP / TERM exit behavior. Keep this module aligned with `scripts/temp-env.sh`, `runtime/temporary.c` and the canonical contract. |
| `tests/contract/temp_hygiene.py` | Eleven infrastructure regressions for allocators, driver failure paths, concurrent fixtures and private proxy port publication. Run from the repository root with `./scripts/test-env.sh python3 tests/contract/temp_hygiene.py` (or directly with `python3 tests/contract/temp_hygiene.py`). `make test` includes it as suite `temp_hygiene`. | Maintainers of workspace allocators, driver staging, FILE storage and harness wrappers own the corresponding regressions; update them together with contract changes. Keep migration auditing and active-owner assertions, not merely “directory disappeared” checks. |

Current importing clients are `tests/contract/temp_hygiene.py`,
`tests/optional/{initck,mathck}_overhead.py` and
`tests/service/proxy/run_conformance.py`. Keep their imports even when a
different suite loses its Python generator. Proxy and benchmarks have separate
scope/ownership decisions; none is retired by this infrastructure decision.

The regression needs built native driver/stages, a C compiler (`CC`, default
clang), GNU/Linux process/filesystem tools and Python 3. Its unsafe-root case
uses bubblewrap (`bwrap`; install the `bubblewrap` package, which is
recommended) and skips when `bwrap` is not installed or cannot run;
Emacs allocator coverage is conditional on Emacs being installed. Report these
coverage limitations rather than treating a sandbox skip as security validation.

**Future replacement map:** preserve every row below before replacing either
retained component. Test names refer to `TemporaryHygiene` in
`tests/contract/temp_hygiene.py`; detailed ownership rules remain in the canonical
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
| Corpus twins: retain full corpus, migrated to shell | `./tests/contract/mathck_twins.sh`, also suite `mathck_twins`; [on/off twin contract](mathck.md#mathck-onoff-twins). | MATHCK/corpus maintainers preserve fixture discovery, dialect/args/stdin handling, per-cell isolation, nonempty/result gates and paired outcomes. Do not prune cases to remove Python or treat unchecked overflowing outputs as oracles. |
| G1–G29 baseline: retain classification audit, migrated to shell/JSON | `./tests/contract/mathck_baseline.sh`, also suite `mathck_baseline`; [gap baseline](mathck.md#mathck-gap-baseline). | MATHCK maintainers own `mathck_baseline.json` and fixtures together: keep all gap IDs, independently justified outcomes, bounds and compile-only categories; reclassify a fixed gap in the fixing change. Observed gaps are not language contracts. |
| Bootstrap source audit: retain, migrated to shell/jq/awk | `./tests/contract/mathck_bootstrap_audit.sh`, also suite `mathck_bootstrap_audit`; [bootstrap contract](../bootstrap_subset.md#self-hosting-arithmetic). | Compiler/pasboot maintainers own unchecked label-key scope, restored flags, actual wide-limit IR, gen1–gen4 label keys, malformed directives and declared runtime/cell totals. Do not confuse this focused audit with the destructive `test-bootstrap` gate. |
| No-core infrastructure: retain Python | `./tests/unit/no_core.py`, suite `no_core` in `make test`. Tests launcher/descendant dumpability, direct SIGABRT/stdout/stderr, opt-out and mixed destructive-goal rejection. | Test-launcher maintainers own `scripts/test-env.sh`, `tests/lib/no_core.c`, shim publication and regression together. Preserve exact signals/diagnostics and per-exec suppression without production-runtime or system-wide crash-setting changes. Non-Linux dumpability coverage skips explicitly. |
| Overhead measurements: retain both Python drivers, opt-in | `python3 tests/optional/initck_overhead.py` and `python3 tests/optional/mathck_overhead.py`; [method, fixtures and reports](overhead.md#opt-in-overhead-measurements). Neither is a mandatory test. | Benchmark maintainers own inputs, independent correctness checks, timing/size/memory method and environment/revision reporting. Keep raw samples and limitations; do not turn host timings or reference-compiler outputs into numeric correctness thresholds. |
| Structural AST: retain six Python checkers; native astcompare and check fixtures also remain | Owning suites and obligations below; [native AST comparison runner](../../tests/corpus/astcompare.sh) is separate from these relational checks. | AST/read-site maintainers preserve schema/provenance, exact mutation scope/counts and traversal semantics. A generic JSON walk or ordered text matcher is not automatically an equivalent checker. |

The no-core regression has no Pascal-compiler/bootstrap requirement: it uses the
independently built test-only shim (and Python child processes). Its direct
execution also checks the launcher itself, so it removes enclosing preload and
opt-out settings before its probes; static/set-ID preload limitations still
apply. It does not need native_temp because it allocates no scratch workspace.

**Python checker ownership:** the 27 Python checkers that suites used to
carry as inline heredocs are files beside the programs they check, in
`tests/contract/fixtures/<suite>/*.py` (for example
`initck_heap/ptr-ir.pas` and `initck_heap/ptr-ir.py`). The maintainer of
each owning suite owns its checkers; run them through the suite,
`./tests/contract/<suite>.sh`. Keep the existing caller flags,
compile/runtime matrices and disabled-invalid compile-only paths when
changing any checker.

| Structural checkers / owning suite | Purpose and maintenance obligation |
| --- | --- |
| Two in `initck_contract.sh` | Legacy/mixed read-flag mutation and exact provenance before/after typecheck: retain traversal alternation, absent snapshots, excluded resolved_type traversal and true/false mixture. |
| Two in `initck_scalar.sh` | Parser/typed read location and enabled flag assertions, typed zero-selector Designator/no-location variants, and recursive legacy flag removal. Preserve the typed-tree origin and don't remove enabled flags when stripping coordinates. |
| One in `initck_routines.sh` | Strip only enabled RETURN/Block snapshots, exactly two; preserve no-guard/default-return and original guard-count checks. |
| One in `stage_cli.sh` | Remove only read_location columns for structural equality, require nonempty wide columns exactly {40000}; retain the suite's conditional pass/fail handling. |

Nineteen retained IR/dataflow/mutation/presence checkers belong to
`initck_{definite,external,heap,producers,routines,scalar,validation}.sh` and
`super_new_contract.sh`. These owners must preserve function scope, first/last
occurrences, SSA identity, branch/unreachable shape, state publication, helper
counts and mutation match gates as applicable, not just substring order.
Two incidental text checkers remain: the ABI normalizers
`initck_abi/abi-signatures.py` and `initck_routines/abi-signatures.py`. Retain their ordered signatures/call multiplicity,
SSA-name normalization differences and layout assertions until equivalent
checks are demonstrated. This ownership map covers all 27 remaining
checkers, not a promise to keep them indefinitely or a Python-free suite claim.

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
recursion limit, and review of `tests/corpus/reference/depth/*`; confirm the native
`./tests/corpus/depth.sh` assertions rather than blessing the
reference's behavior as the contract. It writes persistent fixtures, so it
has no native_temp import. The shell refresh entry points
`update-reference-{ast,codegen,gpu}.sh` likewise retain reference-compiler Python
as explicit maintenance: review source/JSON changes and run the owning native
AST/checklit/GPU suite (report GPU prerequisite skips). Routine test recipes
consume frozen inputs, not these refresh commands. Their invocation details
remain in the corresponding suite sections and script headers.

Together with the [temporary infrastructure](#retained-python-temporary-infrastructure)
and [proxy](../../tests/README.md#completion-proxy-conformance-retained)
sections, this accounts for every retained standalone Python component. The
Python parity suite and its `tests/support.py` were retired on 2026-10-04;
[what they checked of native behavior](../../tests/README.md#ported-from-the-retired-python-parity-suite)
now lives in native fixtures and suites.
The audit below records actual shared-support/wrapper boundaries and unresolved
findings. Any future removal or lifecycle correction still needs its own
validation; documentation is not a runtime validation gate.

### Proxy wrapper audit

Proxy wrapper ownership is separate from report destinations. The five
`tests/service/proxy_*.sh` suites all source the harness, and so temp-env;
their work, runner binaries,
logs and shell-created port files are in supervised workspaces. Six build
wrappers compile native Pascal units into caller-supplied output paths and
allocate no shell scratch. Four require the fixture-directory cwd; the two
conformance builders derive it from their own path. `tests/corpus/fixtures.sh` supplies
that cwd and absolute compiler/output paths to fixture builders, but its
default discovery does not include `tests/service/proxy`. Explicit native wrapper
checks still own these cases; do not remove them because the golden suite did
not discover them. The `service` tier holds all five wrappers.

| Audited boundary / responsible maintainer | Current behavior, coverage or required follow-up |
| --- | --- |
| Private conformance port publication / proxy harness | `Harness.start_stub` publishes `port` in a private per-startup TemporaryDirectory inside its owned `_log_dir`. Context cleanup removes the directory on success or exception; a late file write cannot recreate that missing parent. `test_proxy_stub_port_publication` covers ownership/mode, repeated success, spawn failure, early exit, empty/malformed publication, unready listener and timeout with injected children, plus real repeated/concurrent listeners in one PID. This does not prove child-tree reaping or add a child-registration signal guarantee. |
| Daemon supervision / proxy harness and shell wrapper owners | `build_report` stops registered children in finally; stderr files avoid undrained PIPE deadlocks. `stop_all` terminates/waits then kills on timeout but does not wait after kill or supervise an entire descendant tree. oneshot/smoke cleanup kills without waiting. Workspace cleanup alone is not child-reaping proof; retain bounded lifecycle/signal tests for any correction. |
| Report case uniqueness / proxy protocol maintainers | `compare` checks the union of case-name sets and exact non-note records, but dict construction collapses duplicate names. Calibration is compared via the report; corpus/dead-health checks also use the native replay runner. Native/golden checks do not establish duplicate rejection in the Python comparator. Add an explicit uniqueness gate only with a focused regression, not by claiming coverage already exists. |

The private-port regression can be run without compiler/GPU prerequisites:
`./scripts/test-env.sh python3 tests/contract/temp_hygiene.py TemporaryHygiene.test_proxy_stub_port_publication`.
Its injected timeout avoids a 20-second wait; real listener probes retain the
harness bounds. Diagnostics remain in owned logs and native_temp removes the
process workspace at exit. It neither changes golden comparison nor supervises
children beyond the existing harness teardown.

The other rows are retained audit findings, not retired assertions or passed
lifecycle guarantees. Existing temporary-infrastructure regression gaps remain open. Fixes
may be bounded separately without reducing matrices.
