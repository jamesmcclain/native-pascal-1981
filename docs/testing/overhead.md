# Opt-in overhead measurements

How the INITCK and MATHCK overhead drivers measure cost; they are measurements, not tests. The test suites themselves are described in
[tests/README.md](../../tests/README.md).

## Opt-in overhead measurements

- [Reproduction and interpretation](#reproduction-and-interpretation)
- [INITCK workloads and memory](#initck-workloads-and-memory)
- [MATHCK workloads and optimization](#mathck-workloads-and-optimization)
- [Retained measurement snapshots](#retained-measurement-snapshots)

### Reproduction and interpretation

From the repository root, build the current driver, runtime and stages first:

```sh
make -j16 driver bootstrap
python3 tests/optional/initck_overhead.py > build/initck-overhead.json
python3 tests/optional/mathck_overhead.py > build/mathck-overhead.json
```

Both tools require Python 3, clang, GNU `size` and `/usr/bin/time`, plus the
normal compiler prerequisites. They use Linux `/proc/cpuinfo`; the INITCK
allocation probe also needs linker `--wrap=calloc`/`--wrap=free` support.
They are deliberately outside `make test`: timings are observations,
not correctness gates or release thresholds. Reports under `build/` are
persistent user-selected outputs, not scratch; a clean bootstrap deletes
`build/`, so preserve desired reports first. Temporary binaries/IR use the
[owned workspace contract](../temporary_files.md).

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

`initck_overhead.py` owns the three `tests/contract/fixtures/initck_bench_*.pas` workloads,
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

`tests/contract/fixtures/initck_bench_memory.c` measures requested calloc bytes from the real
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

`mathck_overhead.py` owns `tests/contract/fixtures/mathck/bench_*.pas`, with input `1`:

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
[Optimization regressions](mathck.md#mathck-optimization) pin proven-safe checks folding
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
| [INITCK baseline](../initck-overhead-baseline.json) (2026-10-02) | Before metadata optimization; O2 aggregate/call on/off 1.700, text +3.1%; per-leaf shadow cost motivates investigation. |
| [MATHCK baseline](../mathck-overhead-baseline.json) (2026-10-03) | Before whole-vector checks; VECTOR on/off 9.94 at O0 and 3.54 at O2, text +68.1%/+20.2%. |
| [MATHCK whole-vector run](../mathck-overhead-optimized.json) (2026-10-03) | Same host/method; VECTOR on/off 2.21/1.82, text +71.9%/+21.3%; scalar/builtin/wide effectively unchanged. |

These retained runs used Linux x86-64, Ryzen 7 5800X, clang 21.1.8, seven
samples and no CPU pinning/frequency control. They do not describe current
performance on every host. Any optimization must rerun correctness suites and
measurements without weakening checks; proven-safe guard elimination is a
separate task. Broader claims need application, allocation-heavy, recursive
and external-boundary workloads, a genuinely uninstrumented INITCK comparator,
and repeated controlled-host measurements.
