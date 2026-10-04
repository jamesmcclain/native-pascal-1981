# MATHCK overhead: baseline and optimization

Measured compiler/runtime: `818f884` on `port-mathck`, Linux x86-64, AMD
Ryzen 7 5800X, Ubuntu clang 21.1.8. This is an opt-in microbenchmark, not a
performance release threshold or a whole-program claim. Raw samples, sizes
and environment are in
[`mathck-overhead-baseline.json`](mathck-overhead-baseline.json).

## Reproduce

```sh
make -j16 bootstrap && make -j16
python3 tests/mathck_overhead.py > /tmp/mathck-overhead.json
```

Requires Python 3, clang, GNU `size` and `/usr/bin/time`. Run on an idle
host. Each `tests/fixtures/mathck/bench_*.pas` workload is compiled with its
`{$MATHCK+}` and with `{$MATHCK-}` at O0 and O2. Unlike INITCK's comparison,
**MATHCK- is a true unchecked comparator**: wrapping arithmetic with no
overflow intrinsics (the mandatory zero-divisor checks are in both builds).
No workload overflows, so the script requires the same exact stdout and empty
stderr from both builds on every run. Each binary gets one untimed warmup
and seven samples, alternating on/off. Wall times include process startup
and the GNU time launcher (about 1-2 ms), not compilation. No CPU pinning.
Timing samples are observations, not assertions.

- **Scalar** (vintage): 20 million `k := k + a[i] * 2 - a[i - 1]` over a
  1024-element INTEGER array; one element is negated per row.
- **Builtins** (vintage): 20 million rows of `SQR`, `ABS` and `PRED` in a
  subscript.
- **Wide** (extended): 20 million INTEGER32 multiply-accumulates folded into
  an INTEGER64 total.
- **Vector** (extended): 20 million steps of an 8-lane INTEGER32 VECTOR
  recurrence (`p := p + q * c; q := q - p`).

## Results

`text` is GNU size's linked text total, including runtime code. "Checks" is
the number of `pas_math_overflow` failure calls in the IR the codegen emits
(before LLVM optimization; the `-S` output is not optimized).

| Workload | Opt | Off median s | On median s | On/off | Off text | On text | Text change | Checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Scalar | O0 | 0.2659 | 0.3594 | 1.35 | 19688 | 20392 | +3.6% | 10 |
| Scalar | O2 | 0.0025 | 0.0110 | 4.33 | 9059 | 9764 | +7.8% | 10 |
| Builtins | O0 | 0.2556 | 0.5655 | 2.21 | 19624 | 20728 | +5.6% | 16 |
| Builtins | O2 | 0.0042 | 0.0291 | 6.90 | 9115 | 10004 | +9.8% | 16 |
| Wide | O0 | 0.0469 | 0.0612 | 1.30 | 10600 | 11224 | +5.9% | 9 |
| Wide | O2 | 0.0048 | 0.0089 | 1.88 | 9925 | 9688 | -2.4% | 9 |
| Vector | O0 | 0.1126 | 1.1190 | 9.94 | 8803 | 14796 | +68.1% | 41 |
| Vector | O2 | 0.0413 | 0.1461 | 3.54 | 8743 | 10512 | +20.2% | 41 |

## Reading the numbers

- **O2 scalar ratios mostly measure lost vectorization.** The unchecked O2
  loops finish 20 million iterations in a few milliseconds, close to the
  process-startup floor. That is consistent with LLVM vectorizing and
  reassociating wrapping arithmetic, which a per-operation overflow branch
  prevents. The absolute cost is small: about 9-25 ms per 20 million
  iterations (0.4-1.2 ns per iteration). The ratios are large because the
  baseline is nearly free, so they should not be read as per-check cost.
- **VECTOR is the largest cost.** MATHCK+ lowers each integer VECTOR
  operation one lane at a time with an overflow branch per lane (a
  correctness requirement: a failing lane must be named and nothing stored).
  MATHCK- keeps one SIMD instruction per operation (3 vector integer
  operations in the emitted IR, 0 under MATHCK+). The cost is about 10x at
  O0, 3.5x at O2 and +20-68% text. `{$MATHCK-}` around a hot VECTOR kernel
  is the documented opt-out.
- **Builtins** cost more than plain operators because SQR, ABS and PRED each
  add a checked operation and PRED in a subscript adds another.
- Peak RSS is about 1.9 MiB with no on/off difference; MATHCK keeps no
  metadata.

## Gate outcome

The baseline above was recorded before any MATHCK optimization, with no
compiler behavior changed.

## After optimization (§8 optimization item)

Same host and method, 7 samples, results in
[`mathck-overhead-optimized.json`](mathck-overhead-optimized.json):

| Workload | Opt | Off median s | On median s | On/off | Off text | On text | Text change | Checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Scalar | O0 | 0.2663 | 0.3602 | 1.35 | 19688 | 20392 | +3.6% | 10 |
| Scalar | O2 | 0.0026 | 0.0115 | 4.48 | 9059 | 9764 | +7.8% | 10 |
| Builtins | O0 | 0.2565 | 0.5657 | 2.21 | 19624 | 20728 | +5.6% | 16 |
| Builtins | O2 | 0.0041 | 0.0288 | 6.95 | 9115 | 10004 | +9.8% | 16 |
| Wide | O0 | 0.0472 | 0.0618 | 1.31 | 10600 | 11224 | +5.9% | 9 |
| Wide | O2 | 0.0046 | 0.0084 | 1.84 | 9925 | 9688 | -2.4% | 9 |
| Vector | O0 | 0.1127 | 0.2490 | 2.21 | 8803 | 15132 | +71.9% | 41 |
| Vector | O2 | 0.0415 | 0.0754 | 1.82 | 8743 | 10608 | +21.3% | 41 |

- **Whole-vector check.** A MATHCK+ integer VECTOR `+ - *` or negation now
  computes every lane with one vector `[su]{add,sub,mul}.with.overflow`
  intrinsic and branches once on the OR of the overflow lanes. Only when
  some lane overflowed does a cold path redo the operation lane by lane, so
  the lowest failing lane still traps with its own operands and nothing is
  stored. Vector on/off fell from 9.94 to 2.21 at O0 and from 3.54 to 1.82
  at O2. Text grows slightly, because the cold lane-by-lane path stays (its
  checks are still counted in "Checks"). DIV/MOD stay lane by lane, since a
  vector division by a zero lane is LLVM undefined behavior.
- **Scalar, builtins, wide** are unchanged, as expected: their checks were
  already left to LLVM. LLVM deletes a check when it proves the operation
  cannot overflow. `tests/mathck_optimization.py` pins that operations
  bounded by constant FOR limits fold at O1-O3 while unprovable checks stay.
- **No compiler range facts were added.** Constant FOR bounds already reach
  LLVM's scalar evolution, which is what folds those checks. A declared
  subrange is not a trustworthy fact: under RANGECK- (or through an
  uninitialized or variant-record value) a subrange variable can hold any
  value of its host type, so asserting its range would turn a MATHCK
  failure into undefined behavior. The remaining O2 scalar cost is lost
  vectorization of loops whose checks LLVM cannot prove, such as
  accumulations. `{$MATHCK-}` around a proven-hot kernel remains the
  opt-out.

Any further optimization must rerun the correctness suites and these
measurements. For broader claims, add application workloads and
controlled-host repeats.
