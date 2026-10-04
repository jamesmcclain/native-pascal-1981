# INITCK overhead baseline (before metadata optimization)

Measured compiler/runtime: `b8018b0` on `port-initck`, Linux x86-64,
AMD Ryzen 7 5800X, Ubuntu clang 21.1.8. This is an opt-in microbenchmark,
not a performance release threshold or a whole-program coverage claim.
Raw samples, ELF/IR sizes, environment and allocation measurements are in
[`initck-overhead-baseline.json`](initck-overhead-baseline.json).

## Reproduce

```sh
make -j16 driver bootstrap
python3 tests/initck_overhead.py > /tmp/initck-overhead.json
```

Requires Python 3, clang, GNU `size` and `/usr/bin/time` in addition to the
normal compiler prerequisites. Run on an otherwise idle host. Temporary
files are removed automatically; no unchecked uninitialized data is executed.
The script validates exact output and empty stderr on every invocation.

Three persistent, fully initialized vintage-dialect fixtures are compiled with
INITCK on/off at O0/O2. Both builds use identical loop counts, input and other
checking flags. Each binary has one untimed warmup followed by seven samples;
execution order alternates on/off to reduce order bias. Wall times include
process startup and the GNU time launcher, not compilation. No CPU pinning or
frequency control was applied. Timing samples are observations, not assertions.

- **Scalar:** 60 million bounded integer updates after text input.
- **Aggregate/call:** 30 million VAR-formal updates and two whole-record
  copies per update, exercising two-leaf shadow transport.
- **Heap:** one 30,000-element SUPER ARRAY of 64-INTEGER rows; twenty complete
  write/read passes (38.4 million writes and reads each), then DISPOSE.

## Runtime and code size

`text` is GNU size's linked text/readonly section total, including pulled-in
runtime code, not just the Pascal routine. ELF file bytes and IR text bytes
are also recorded in the JSON; ELF alignment can hide small code changes.

| Workload | Opt | Off median s | On median s | On/off | Off text bytes | On text bytes | Text increase |
|---|---:|---:|---:|---:|---:|---:|---:|
| Scalar | O0 | 0.334220 | 0.277149 | 0.829 | 8519 | 9326 | 9.5% |
| Scalar | O2 | 0.202290 | 0.202353 | 1.000 | 8755 | 9650 | 10.2% |
| Aggregate/call | O0 | 0.407872 | 0.396428 | 0.972 | 9950 | 10188 | 2.4% |
| Aggregate/call | O2 | 0.254652 | 0.432813 | 1.700 | 9874 | 10184 | 3.1% |
| Heap | O0 | 0.816800 | 0.653255 | 0.800 | 9745 | 10747 | 10.3% |
| Heap | O2 | 0.240523 | 0.253852 | 1.055 | 8414 | 9241 | 9.8% |

**Off is not uninstrumented.** Both modes allocate and propagate initialization
state. This comparison measures the net effect of enabling reads, including
changes in taint collection, helper arguments and optimizer decisions; it does
not isolate the branch instruction cost or measure total INITCK instrumentation
cost against an older compiler. On can be faster in this implementation:
unchecked expression/copy paths still collect and propagate unknown state,
whereas successful checked consumers can establish initialized state. These
numbers do not establish that checking generally improves performance. The O2
aggregate case is a clear workload-specific regression worth investigating,
not permission to weaken strict copies or alias-state transport.

## Memory

GNU time's median peak RSS was approximately 1928–1932 KiB for scalar/aggregate
runs and 7288–7292 KiB for heap runs, with essentially no on/off separation.
That is expected because both modes own the same shadows. RSS includes process,
runtime and allocator/page effects; it cannot isolate small stack shadows and
must not be interpreted as zero metadata overhead.

`tests/initck_bench_memory.c` separately measures actual requested calloc
bytes from the real heap registry linked from `runtime/build/libpascalrt.a`,
using test-only linker wrappers. One registration for the heap fixture's
1,920,000 logical leaves requested:

| Allocation footprint | Bytes |
|---|---:|
| Pascal data payload (1,920,000 INTEGERs × 2, layout-derived) | 3,840,000 |
| Shadow payload (measured) | 1,920,000 |
| Registry retained after DISPOSE (measured) | 2,048 |
| Total/peak registry + shadow requested (measured) | 1,922,048 |

The shadow alone is **50% of this INTEGER payload**, plus registry overhead.
Disposal frees the shadow but retains the registry table. This probe excludes
allocator headers, fragmentation, stack/TLS metadata, scratch/released lookups
and registry growth with many allocations. It measures requested bytes, not
resident bytes. It deliberately makes no estimate of total instrumentation
memory for arbitrary programs or types (one byte per leaf has different ratios
for BOOLEAN/CHAR versus pointers/descriptors).

## Gate outcome and next work

Memory, code-size and runtime observations are now recorded before any metadata
optimization. No guard elimination, representation change or support expansion
was made. This baseline identifies per-leaf shadow cost and the optimized
aggregate/call case as candidates for future work. Any optimization must rerun
the correctness suites and these measurements; proven-safe guard elimination
remains a separate task. For broader claims, add allocation-heavy, recursive,
external-boundary and application workloads, a true uninstrumented comparator,
and repeated measurements on controlled hosts.
