# Test Suites for `native-pascal-1981`

This directory contains the automated test suites for the native Pascal 1981 compiler toolchain.

## Validation cost and concurrency

`make -jN` parallelizes Make targets, not shell loops. `make test-native`
now passes `TEST_JOBS` to the main golden/integration/dialect runner (default
8); override with `make -j8 test-native TEST_JOBS=8`, or use `TEST_JOBS=1`
for serial debugging. Other focused suites and optimization matrices still
run sequentially. These are independent concurrency budgets, not a shared
Make job pool.

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

Measured on the development host with warm native tools: the main 331-fixture
runner at eight workers took 11.53 seconds with suppression, versus 56 seconds
without it. The 192-cell DIV/MOD suite took 16.83 seconds; its 176 expected
aborts alone previously cost about three minutes. The complete aggregate gate
(`make -j8 test test-gpu test-reference-parity test-elisp`) passed in 130.49
seconds, including real CUDA, 89 ERT tests, proxy conformance/64 corpus items,
and hook regression tests. Reference parity retains its default disabled
status (the Python implementation is not authoritative). The separate clean
`make -j8 test-bootstrap` regression passed in 190.21 seconds with byte-identical
gen3/gen4 binaries and no Python dependency; its CPU time was 294.50 seconds,
not crash-reporter waiting. Eight concurrent cold-start launchers also passed
the atomic-publication check. These are observed host timings, not
timing-sensitive correctness oracles.

## MATHCK test map

Every script below runs in `make test-native` (in this order) and can be run
alone through `./scripts/test-env.sh ./tests/<name>.sh`. They need built
`bin/` tools and Python 3. Oracles come from exact arithmetic and the
[contract](../docs/mathck_contract.md), not from earlier compiler output.
The user-facing summary is the MATHCK section of
[`docs/dialect_notes.md`](../docs/dialect_notes.md#mathck-integer-overflow-and-division-checks-both).

| Contract area | Script | Details |
|---|---|---|
| Gap inventory G1–G29, observed vs. expected | `mathck_baseline.sh` | [baseline](#mathck-gap-baseline) |
| WORD division and ordering are unsigned | `mathck_word_scalar.sh` | [WORD prerequisites](#scalar-word-arithmetic-prerequisites) |
| FOR stops at the final value without MATHCK | `mathck_for_endpoints.sh` | [FOR endpoints](#for-endpoint-termination) |
| DIV/MOD zero divisor and MIN/-1, both settings, no LLVM UB | `mathck_divmod_safety.sh` | [DIV/MOD safety](#scalar-divmod-safety-prerequisite) |
| Constant folding: truncating DIV/MOD, exact fit, constant zero divisor | `mathck_constant_folding.sh` | [constant folding](#constant-divmod-folding-prerequisite) |
| MATHCK-sensitive arithmetic in the compiler sources and pasboot | `mathck_bootstrap_audit.sh` | [bootstrap audit](#bootstrapself-hosting-arithmetic-audit) |
| Per-operation `mathck`/`op_location` snapshots in the AST | `mathck_metadata.sh` | [metadata](#per-operation-mathck-metadata) |
| Scalar `+ - * DIV` and negation at every width, trap vs. wrap | `mathck_overflow.sh` | [overflow](#mathck-overflow-enforcement) |
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
| Code-review regressions (enum constants, one zero-divisor error, SADDOK VAR C) | `mathck_review.sh` | [review regressions](#mathck-review-regressions) |

MATHCK also shapes fixtures outside these scripts: the checklit vector
shapes (`checklit/vector_arith.pas`, `vector_reduce.pas`), the NVPTX checklit
fixtures (`checklit/device_*.pas`) and the CUDA tests (`gpu/vadd.pas`,
`gpu/aggregate.pas`) carry `{$MATHCK-}`, because they pin unchecked SIMD
instructions or must compile for the GPU. `make test-gpu` runs the CUDA
tests. `tests/mathck_overhead.py` (opt-in, not in `make test-native`)
measures code size and runtime with MATHCK on and off; see
[the baseline](../docs/mathck_overhead.md).

## MATHCK gap baseline

`./tests/mathck_baseline.sh` (also in `make test-native`) runs the persisted
G1–G29 inventory from the `port-mathck` decision record against the native
compiler. Requires Python 3 and built `bin/` tools. The manifest is
[`mathck_baseline.json`](mathck_baseline.json); sources are in
[`fixtures/mathck/`](fixtures/mathck/), with G29 reusing the existing READ
input-overflow goldens. Every applicable probe runs in both dialects at O0/O2;
wide types and extended constant probes are extended-only.

This is a **known-gap baseline at `e615783`, not MATHCK conformance**. Each
manifest entry names its gap ID, classification, current oracle (where safe),
and intended target. Split entries cover all operators/types listed in the
inventory: WORD add/sub/multiply, signed/unsigned DIV/MOD by zero, MIN DIV/MOD,
SUCC/PRED, four OK builtins, three wide INTEGER widths, constant overflow
forms, and TRUNC/ROUND.

- `known-gap-output` pins today's wrong but defined results. The fixing change
  must flip the classification and oracle to correct output or a diagnostic;
  these results must never become the arithmetic contract.
- `known-gap-reject` pins a missing builtin or incorrect typing/folding
  rejection. `correct-reject` records the already-correct constant range errors.
- `known-gap-crash` requires signal termination without a runtime diagnostic,
  ignoring signal number/stdout. No current probe retains this classification:
  G6 now requires a deterministic zero-divisor diagnostic and flushed prefix.
- `known-gap-compile-only` compiles to objects and **never executes** in
  this matrix. No current probe retains it: G9 is now a compile-time
  rejection, and G26 (TRUNC/ROUND of 100000.0) the always-on located
  conversion error. G7 MOD now requires zero, G7 DIV the MATHCK+
  signed overflow diagnostic, and G8 requires the mandatory zero-divisor
  diagnostic. No UB-derived output is an oracle.
- `known-gap-timeout` bounds G19 to one second and requires nontermination;
  the loop body does not print. Replace it with the three-iteration oracle
  when final-value stepping is corrected.
- `correct-output` (G14–G17, G21, G28), `correct-runtime-error` (G29), and
  `out-of-scope-output` (G27: `1.0 / 0.0` is `INF`; G27.overflow: REAL
  overflow is `INF`/`-INF` under MATHCK+, since REAL arithmetic is outside
  MATHCK) preserve existing behavior without claiming any MATHCK protection. READ errors use exact diagnostics, not a specific signal.

Unexpected acceptance, new diagnostics, or loop termination deliberately fail
the baseline: inspect the change and update the corresponding gap entry rather
than weakening the oracle. Execution has a five-second timeout (one for G19),
compilation a thirty-second timeout, and temporary artifacts are removed.
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
are tested. See [`../docs/word_arithmetic_audit.md`](../docs/word_arithmetic_audit.md)
for the site audit and deferred gaps. G14–G17 and G21 are now correct-output
oracles. This is not overflow enforcement or zero-divisor safety: all executed
divisors here are nonzero, and constant-folding/mixed-type gates stay open.

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
WORD loops and unsigned WORD ordering. G18 and G19 are now correct-output
oracles; FOR termination is independent of MATHCK.
Python-reference parity is not used.

### Scalar DIV/MOD safety prerequisite

`./tests/mathck_divmod_safety.sh` (also in `make test-native`) generates native
oracles for all signed/unsigned scalar widths: 176 runtime cells across both
MATHCK settings and O0–O3 (16-bit in both dialects, 8/32/64-bit extended).
Covers MIN DIV -1 returning MIN and MIN MOD -1 returning zero, ordinary
truncating sign combinations, unsigned high-bit values, zero failure with
exact stderr and flushed stdout, and single left-to-right operand evaluation.
O0 IR checks division uses a sanitized divisor after the zero branch.
Constant zero divisors are now rejected by the constant-folding prerequisite.
NVPTX scalar DIV/MOD rejects before IR publication under either setting;
CPU-device lowering uses the host safety path. VECTOR lane safety stays open.

This is **not enabled overflow enforcement**: operator-site MATHCK flags are
not consumed yet, so scalar arithmetic is still unchecked except for mandatory
zero-divisor errors. Those errors report the DIV/MOD token's line and column
from the operator snapshot; a legacy typed AST without one reports
`line 0 column 0` (checked in IR for both). MIN DIV -1 overflow under MATHCK+
remains a later gate.
G6/G8 diagnostics and G7 defined results replace the old UB/crash classes;
G9 now requires compile-time rejection in the constant-folding tests below.
Frozen ASTs are unchanged and obey the same safe unchecked lowering.

### Constant DIV/MOD folding prerequisite

`./tests/mathck_constant_folding.sh` (also in `make test-native`) checks
truncation toward zero and dividend-signed MOD in both folders, independently
of MATHCK: 24 runtime cells at O0–O3 and 128 constant-zero rejection cells.
Literal and named constants, all sign combinations, exact division, MIN MOD
-1, G22, large negative array indices and mixed-width/assignment adaptation
are covered. Direct parser-derived AST probes exercise CONST values consumed
by CASE labels and array bounds, and test zero rejection in the typechecker
and codegen independently. The source CONST/CASE/bound grammar does not admit
binary expressions; it is not broadened by this change.

G9 is a correct compile-time rejection and G22 a correct-output oracle.
The older wide-folding golden now expects `-5 DIV 2 = -2` and `-5 MOD 2 = -1`,
not Python floor semantics. See the [consumer audit](../docs/constant_folding_audit.md).

### Bootstrap/self-hosting arithmetic audit

`./tests/mathck_bootstrap_audit.sh` (also in `make test-native`) pins the
source dependencies in the [audit](../docs/mathck_bootstrap_audit.md): narrow
MATHCK- label-key expressions and restored MATHCK+ counters, wide i64 limit
construction in actual compiler-unit IR, label AST keys at generations 1–4
in both dialects, and 16 high-bit LABEL/GOTO runtime cells (both settings,
both dialects, O0–O3). It also runs pasboot's ignored-MATHCK wrapping fixture
at Clang O0–O3 and checks malformed settings. `make test-pasboot` runs the
same fixture at O1 plus the standard bootstrap feature/rejection matrix.
G1–G5, G7 DIV and G20 now require the MATHCK+ overflow diagnostic; see
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

`./tests/mathck_overflow.sh` (also in `make test-native`) generates native
programs from exact-arithmetic oracles at every scalar width (16-bit in both
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
linked program must print the wrapped results at O0–O3. At O0, every checked
operation's IR must branch on the intrinsic's overflow bit to a block that
calls `pas_math_overflow` and ends in `unreachable`, and the result may be
extracted only in the success block; a checked signed DIV branches on
`%div.min` before dividing. [`fixtures/mathck/twin_arith.pas`](fixtures/mathck/twin_arith.pas)
(GCD, Fibonacci, MIN/MAX boundaries, WORD sums, truncating DIV/MOD) never
overflows and must print `twin_arith.out` under both settings, both dialects
and O0–O3. Constant operands: fully constant overflows (`WRITELN(32767 + 1)`,
`WRITELN(-N)`, `(M + 1) - 1`, the operand of `k := i + (M + 1)`, INTEGER8 and
INTEGER32 forms) must be rejected as "integer constant out of range" with no
IR under either setting; valid constants print their exact value at the
context type (`j := i + (M + 1)` is 32773 for INTEGER32 `j`); a partially
constant `i + (M - 4)` traps under MATHCK+ and wraps under MATHCK-. Wide
extremes are built at run time because INTEGER64 literals above 2^53 lose
precision.

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
REAL operand) are covered too. Builtins the
[audit](../docs/mathck_builtin_audit.md) places outside MATHCK (ORD, WRD,
ODD, HIBYTE, LOBYTE, BYWORD, FLOAT) must print their defined results at
INTEGER/WORD extremes under MATHCK+ with no overflow call in the IR.

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
overflow intrinsic, and has no vector `sdiv`/`srem`.

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

### MATHCK in DEVICE code

`./tests/mathck_device.sh` (also in `make test-native`) compiles NVPTX DEVICE
modules (`--device-triple nvptx64-nvidia-cuda -S`; no GPU needed): every
operation MATHCK+ would check (`+ - *`, DIV, MOD, unary `-`, SUCC, PRED, ABS,
SQR at INTEGER/INTEGER32/WORD) must fail with exactly `MATHCK unsupported
boundary: DEVICE arithmetic at line L column C` and leave no IR; the MATHCK-
twins compile with no overflow intrinsic (DIV/MOD keep the mandatory-safety
rejection); constant folds, WORD ABS, REAL arithmetic, TRUNC and ORD are not
boundaries; a per-statement `{$MATHCK-}` opts out only its own operation. A
CPU DEVICE kernel launched from host code traps with the host diagnostic
under MATHCK+ and wraps under MATHCK- (O0/O2).

### MATHCK address arithmetic boundary

`./tests/mathck_address_arith.sh` (also in `make test-native`): `^CHAR` +
WORD offsets 40000 and 32768 (either operand order) and ADRMEM + 40000 read
the right element under both settings at O0–O3; the MATHCK+ O0 IR for
`p + n` and `p + (n - 1)` has two non-inbounds GEPs and exactly one overflow
intrinsic (the offset's `-`); `p - 1`, `p * 2`, `p DIV 2`, `2 - p` and
`p + 1.5` are rejected by the typechecker; a CINT returned by C `abs` and
incremented in Pascal traps under MATHCK+ and wraps under MATHCK-.

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
([contract](../docs/mathck_contract.md#approved-runtime-diagnostics)).

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
`fixtures/mathck/twin_arith.pas` runs in `mathck_overflow.sh`. Disabled
twins of *overflowing* programs run only in the suites that pin the defined
MATHCK- wrap (`mathck_overflow`, `mathck_builtins`, `mathck_vector`,
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
appears only behind that branch. `mathck_vector.py` pins the lowest-lane
diagnostics.

### MATHCK review regressions

`./tests/mathck_review.sh` (also in `make test-native`) pins the findings of
the `/code-review` of the MATHCK range:
- **Enum constants are checked.** An operation on enum constants
  (`ORD(b) * 20000`, `32767 + ORD(g)`, negation and `DIV` by -1) is not
  folded by the typechecker, so it is checked at run time. It traps under
  MATHCK+ and wraps under MATHCK-, at O0 and O2, and is a DEVICE boundary
  on NVPTX.
- **ORD of an enum is INTEGER.** `ORD(e) * 20000` on an enum variable traps
  rather than being checked at 32 bits and truncated.
- **One zero-divisor error.** A constant zero divisor gives exactly one
  `Constant division by zero` in both dialects.
- **SADDOK-family VAR C.** A subrange variable or field as the VAR C of
  SADDOK, SMULOK, UADDOK or UMULOK is a typechecker type-mismatch error,
  not a codegen abort.

## Host descriptor contracts

`make test-descriptor-contract` runs host SUPER ARRAY ABI/propagation, unsafe
import/export and boundary-rejection probes, including DEVICE preservation.
It is also part of `make test-native`. See
[descriptor/README.md](descriptor/README.md) for coverage, the historical red
baseline and how to run the focused goldens.
`make test-super-new` (also in `make test-native`) checks mandatory bounds/size/
allocation failures, once-only evaluation and transactional slot publication with
test-only linker failure injection; no production allocator test hook.

## INITCK overhead measurement (opt-in)

`python3 tests/initck_overhead.py` measures initialized scalar, aggregate/call
and SUPER heap workloads with checking on/off at O0/O2. It validates outputs,
reports seven interleaved timing/RSS samples and linked code sizes, and runs a
test-only allocation probe against the real heap-shadow registry. It requires
Python 3, clang, GNU `size` and `/usr/bin/time` and is deliberately not part of
`make test-native`: noisy performance measurements are not correctness gates.
See [the baseline and comparison limits](../docs/initck_overhead.md). Both on
and off track state, so these are not uninstrumented-baseline comparisons.

## INITCK support boundary

### Post-integration bootstrap and native release gate

Validated after integration through `73bcf41`, from a clean build:

```sh
make clean
make -j16 bootstrap check-bootstrap-subset
make -j16 test-native
```

All 29 gen1 compilands passed the bootstrap subset check. The bootstrap
rebuilt gen1 through gen4, and byte-for-byte gen3/gen4 comparisons passed for
lexer, parser, typechecker and codegen. The full native suite passed: 331 main
fixtures, 42 checklit fixtures, 21 frozen-AST comparisons, and all focused
contract scripts, including every INITCK script. The release and ABI matrices
passed in both dialects at O0/O1/O2/O3. This records integration validation;
it does not expand INITCK support or close the remaining boundary/optimization
gates. This is historical clean release-gate evidence, not an instruction to
clean and rerun everything for each edit. For subsequent integration gates,
use incremental builds unless clean-build evidence is needed, and choose
fixture concurrency with `TEST_JOBS` (default 8).

`./tests/initck_definite.sh` (also in `make test-native`) tests compiler-owned
scalar-local definite-initialization proofs. O0 IR counts pin removed guards
for direct assignments, known unchecked producers, BOOLEAN/CHAR locals and
both-arm IF joins, while retaining shadow slots/stores and output-call guards.
Both dialects at O0/O1/O2/O3 require exact initialized output and runtime failure
before derived output for a missing branch, GOTO bypass, zero-iteration loop, unchecked
unknown copy, and function-call mutation through VAR. Each unknown read retains
a metadata guard before its native load; disabled bad twins are compile-only.
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
hidden parameters or result changes. The same script covers value formals and
tracked results. A fully checked program passes 0, FALSE, CHR(0) and `-32768`
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
routine. An enabled captured read is the exact `global or captured storage`
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
compiland is exactly `DEVICE code` with no IR. Diagnostics (`bnd`, O0/O2):
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

### 3. Parity Test Suite (`tests/parity/`) -- disabled, slated for removal
- **Status**: disabled. The native compiler is authoritative; the Python compiler (`pascal1981`) is an earlier implementation, not an oracle, and the native stages deliberately diverge from it (for example, parser/typechecker `read_flags` for INITCK), so many comparisons fail by design. `make test-reference-parity` only prints a notice unless `ENABLE_PYTHON_PARITY=1` is set. Do not add fixtures or treat failures as defects.
- **Runner**: `pytest`
- **Description**: compares native compiler stages (`lexer`, `parser`, `typechecker`, `codegen`) with the Python implementation: AST equivalence, code generation, record layouts, deep recursion limits, and device/kernel launches.
- **Running** (manual comparison only):
  ```bash
  make test-reference-parity ENABLE_PYTHON_PARITY=1
  ```
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
- **Description**: Checks hook restaging, partial staging, tool errors, optional tools, and the executable file mode. Each behavior test uses an isolated Git repository.
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
