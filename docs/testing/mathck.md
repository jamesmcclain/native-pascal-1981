# MATHCK tests

How the MATHCK suites map to the arithmetic-checking contract, and the G1–G29 gap baseline. The test suites themselves are described in
[tests/README.md](../../tests/README.md).

## MATHCK test map

Every script below runs in `make test` (concurrently; see above) and can be run
alone through `./tests/<name>.sh`. They need built
`bin/` tools and each suite's shell/native dependencies (including `jq` for
JSON checks), not Python 3. The overall native gate still requires Python for
retained infrastructure and INITCK/structural checks. Oracles come from exact arithmetic and the
[MATHCK contract](../dialect_notes.md#mathck-integer-overflow-and-division-checks-both)
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
shapes (`tests/corpus/checklit/vector_arith.pas`, `vector_reduce.pas`), the NVPTX checklit
fixtures (`tests/corpus/checklit/device_*.pas`) and the CUDA tests (`tests/optional/gpu/vadd.pas`,
`tests/optional/gpu/aggregate.pas`) carry `{$MATHCK-}`, because they pin unchecked SIMD
instructions or must compile for the GPU. `make test-gpu` runs the CUDA
tests. `tests/optional/mathck_overhead.py` (opt-in, not in `make test`)
measures code size and runtime with MATHCK on and off; see
[opt-in measurements](overhead.md#opt-in-overhead-measurements).

## MATHCK gap baseline

`./tests/contract/mathck_baseline.sh` (in `make test`) runs the persisted
G1–G29 classification inventory against the native compiler. Requires `jq` and built `bin/` tools. The manifest is
[`mathck_baseline.json`](../../tests/contract/fixtures/mathck_baseline.json); sources are in
[`tests/contract/fixtures/mathck/`](../../tests/contract/fixtures/mathck), with G29 reusing the existing READ
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
  [`ORD(WORD)` conversion](../dialect_notes.md#deferred-ordword-conversion-gap-g25))
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

`./tests/contract/mathck_word_scalar.sh` (in `make test`) checks unsigned
scalar DIV/MOD and ordering at every WORD-family width. Its native expected
outputs run in both dialects for WORD and extended mode for WORD8/32/64,
at O0/O1/O2/O3 with both MATHCK settings (24 runtime cells). Coverage includes
high-bit/max/low values, both operand orders, all ordering predicates and
EQ/NE, literal adaptation, unsigned width promotion, signed controls and CASE.
O0 IR asserts unsigned instructions at every width and preserved wider
zero-extension/signed array bounds comparisons. Set membership bounds remain
unsigned; supported INTEGER membership and existing WORD admission rejections
are tested. See the [WORD comparison boundaries](../dialect_notes.md#word-arithmetic-and-comparison-boundaries)
and [WORD to REAL rules](../dialect_notes.md#word-to-real-conversion).
The same fixtures pin FLOAT, mixed REAL +/* and wide maxima; O0 IR requires
`uitofp` at 8/16/32/64 bits. G14–G17 and G21 are correct-output oracles.
This suite is not overflow enforcement or zero-divisor safety: all executed
divisors here are nonzero. Dedicated folding, mixed-type and division-safety
suites enforce those separate implemented contracts.

### FOR endpoint termination

`./tests/contract/mathck_for_endpoints.sh` (in `make test`) checks that a
FOR loop leaves at its final value instead of stepping past it and wrapping.
Iteration counts are the oracle; the post-loop control value is undefined
(manual 9-17) and never printed. `tests/contract/fixtures/mathck/for_endpoints.pas` runs in
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

`./tests/contract/mathck_divmod_safety.sh` (in `make test`) runs
checked-in fixtures for all signed/unsigned scalar widths (16-bit in both
dialects, 8/32/64-bit extended) under both MATHCK settings at O0–O3, as
independent parallel units with declared cell totals: 16 defined-result
cells, 160 zero-divisor cells, 4 guarded-IR, 4 NVPTX, 4 host-guard and 4
legacy-coordinate checks.

- `tests/contract/fixtures/mathck/divmod_<dialect>_{checked,unchecked}.pas/.out`: signed
  MIN built at run time, MIN MOD -1 returning zero under both settings, MIN
  DIV -1 returning MIN only in the unchecked fixture, the truncating sign
  table (quotient toward zero, remainder `a - q*b`) and unsigned high-bit
  values. Their `-S -O0` IR must divide only by a sanitized
  `select i1 …, iN 1, iN …` defined earlier in the function, after the
  `div.bad`/`div.ok` branch (an `awk` pass per function), at least four
  divisions per width, with no `poison` or `undef`.
- `tests/contract/fixtures/mathck/divmod_zero.pas` + `divmod_zero.cases`: a template and
  one row per type and operator with the exact diagnostic. A dynamic zero
  divisor fails under both settings with nonzero status, flushed stdout
  `prefix`/`left`/`right` (single left-to-right operand evaluation) and the
  DIV/MOD token's line and column from the operator snapshot.
- A legacy typed AST (snapshots removed with `jq`) keeps exactly one
  zero-divisor guard and reports `line 0 column 0`; the snapshot AST reports
  `line 9 column 21` (both checked in IR, both dialects). Frozen ASTs are
  unchanged and obey the same safe unchecked lowering.
- `tests/contract/fixtures/mathck/divmod_device.pas`: NVPTX scalar DIV/MOD fails before
  output under either setting, with the exact located MATHCK boundary
  (MATHCK+) or mandatory-safety (MATHCK-) message; host codegen of the same
  AST keeps the guard.

Neighbouring contracts live elsewhere: MIN DIV -1 overflow under MATHCK+ is
in [overflow enforcement](#mathck-overflow-enforcement), constant zero
divisors are rejected in the [constant-folding suite](#constant-divmod-folding-prerequisite),
and VECTOR lane DIV/MOD safety is in [VECTOR lanes](#mathck-vector-lanes).

### Constant DIV/MOD folding prerequisite

`./tests/contract/mathck_constant_folding.sh` (in `make test`) checks
truncation toward zero and dividend-signed MOD in both folders, independently
of MATHCK: 24 runtime cells at O0–O3 and 160 constant-zero rejection cells,
each with exactly one `Constant division by zero`.
Literal and named constants, all sign combinations, exact division, MIN MOD
-1, G22, large negative array indices and mixed-width/assignment adaptation
are covered. Direct parser-derived AST probes exercise CONST values consumed
by CASE labels and array bounds, and test zero rejection in the typechecker
and codegen independently. The source CONST/CASE/bound grammar does not admit
binary expressions, and these tests do not broaden it.

The fixtures are in `tests/contract/fixtures/mathck`: `constfold_twins.pas/.out` (each row
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
[constant consumer invariants](../dialect_notes.md#constant-divmod-and-consumer-invariants).

### Bootstrap/self-hosting arithmetic audit

`./tests/contract/mathck_bootstrap_audit.sh` (in `make test`) pins the
source dependencies in the [bootstrap contract](../bootstrap_subset.md#self-hosting-arithmetic): narrow
MATHCK- label-key expressions and restored MATHCK+ counters, wide i64 limit
construction in actual compiler-unit IR, label AST keys at generations 1–4
in both dialects, and 16 high-bit LABEL/GOTO runtime cells (both settings,
both dialects, O0–O3). It also runs pasboot's ignored-MATHCK wrapping fixture
at Clang O0–O3 and checks malformed settings. The `pasboot` unit suite runs the
same fixture at O1 plus the standard bootstrap feature/rejection matrix.
The label program is `tests/contract/fixtures/mathck/bootstrap_labels.pas/.out`. The token
flags and label keys are checked with `jq`, the IR function bodies are
extracted with `awk`, and a malformed setting must print exactly
`<path>:1: malformed $MATHCK`. Units run in parallel with declared totals: 1
flags, 4 wide-limit functions, 8 label-key, 4 pasboot, 4 malformed and 16
native cells.
MATHCK+ overflow diagnostics for user arithmetic (G1–G5, G7 DIV, G20) are in
[MATHCK+ overflow enforcement](#mathck-overflow-enforcement).

### Per-operation MATHCK metadata

`./tests/contract/mathck_metadata.sh` (in `make test`) checks the
per-operation MATHCK snapshot. Arithmetic BinOp (`+ - * DIV MOD`) and
sign-minus UnaryOp nodes carry `mathck` and `op_location` (`line`, `column`)
captured at the operator token, before the right operand or the signed term
is parsed; SUCC/PRED/ABS/SQR FuncCall nodes (any letter case, expression or
CONST context) carry the same fields from the function-name token, before
the arguments. [`mathck_metadata_check.pas`](../../tests/contract/fixtures/mathck_metadata_check.pas)
prints one line per such operation from both the parser and typechecker
output and rejects missing snapshots or snapshots on other operators and
calls. Expected listings are the `.out` files beside
`tests/contract/fixtures/mathck/metadata_{ops,builtins,transitions,const}.pas`; all but the
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

`./tests/contract/mathck_scalar.sh` (in `make test`) runs checked-in
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
`./tests/contract/mathck_overflow.sh` (in `make test`) checks that at O0
every checked operation's IR must branch on the intrinsic's overflow bit to a block that
calls `pas_math_overflow` and ends in `unreachable`, and the result may be
extracted only in the success block; a checked signed DIV branches on
`%div.min` before dividing. It compiles `tests/contract/fixtures/mathck/guards.pas` (`{TYPE}`
= all ten scalar type/dialect pairs) and follows each check to its branch
targets with an `awk` pass over `main`, since CHECK directives match unordered
lines. [`tests/contract/fixtures/mathck/twin_arith.pas`](../../tests/contract/fixtures/mathck/twin_arith.pas)
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

The fixtures are `tests/contract/fixtures/mathck/scalar_<type>_*` for the eight integer
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

`./tests/contract/mathck_builtins.sh` (in `make test`) covers the scoped
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
[builtin classification](../dialect_notes.md#mathck-builtin-classification) places outside MATHCK (ORD, WRD,
ODD, HIBYTE, LOBYTE, BYWORD, FLOAT) must print their defined results at
INTEGER/WORD extremes under MATHCK+ with no overflow call in the IR.
The unchecked CHR and CONCAT capacity gaps are documented there, not pinned
as results.

The cases are fixtures under `tests/contract/fixtures/mathck/builtin_*`, with expected
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

`./tests/contract/mathck_mixed_width.sh` (in `make test`) covers operands
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
there are `tests/contract/fixtures/mathck/mixed_<left>_<right>_{ok,wrap,fail}`. Their
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

`./tests/contract/mathck_vector.sh` (in `make test`) covers integer VECTOR
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

The fixtures are in `tests/contract/fixtures/mathck`, per element type:
`vector_<type>_ok.pas/.out` (the suite prepends either setting; same output)
and `vector_<type>_cases.pas`, one case per stdin value, each preceded by a
comment giving its derivation, with exact transcripts
`vector_<type>_checked.expected` (MATHCK+) and `_unchecked.expected`
(MATHCK-); plus `vector_ir.pas`. The suite runs one unit per type and setting
in parallel, with declared totals: 64 fit cells, 576 case cells and 1 IR
check.

### TRUNC/ROUND range (G26)

`./tests/contract/trunc_round_range.sh` (in `make test`) checks the
always-on TRUNC/ROUND INTEGER range check, both dialects, under
`{$MATHCK+}` and `{$MATHCK-}`, O0–O3: extreme valid results and ROUND's
half-away ties print exactly; `32768`/`-32769` (TRUNC), `32767.5`/`-32768.5`
(ROUND), `±1.0E300` and NaN fail with `runtime error: <TRUNC|ROUND> result
out of INTEGER range at line L column C (value=V)` after the flushed prefix;
a REAL32 argument is widened and checked. O0 IR reaches `fptosi` only in
`conv.ok`. A CPU DEVICE kernel fails the same way through LAUNCH; NVPTX IR
uses `llvm.fptosi.sat.i16.f64` with no plain `fptosi` and no host call.

Fixtures are under `tests/contract/fixtures/mathck/`: `trunc_round_valid.pas/.out`; the
`trunc_round_invalid.pas` template with one row per out-of-range call and
its exact diagnostic in `trunc_round_invalid.cases`;
`trunc_round_real32.pas/.err`; `trunc_round_device/` (interface,
implementation, host template and expectations); and `trunc_round_ir.pas`.
The directive is prepended to each program. Units run in parallel with
declared cell totals: 16 fit, 128 out of range, 8 REAL32, 4 CPU DEVICE, 2
NVPTX, 1 IR.

### MATHCK in DEVICE code

`./tests/contract/mathck_device.sh` (in `make test`) compiles NVPTX DEVICE
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
`tests/contract/fixtures/mathck`: the module templates `device_module.pas` and
`device_enum.pas`; `device_nvptx.expected`, one record per compile (template,
setting and statement, then exit status, whether IR was written and is free
of checks, and exact stderr), which also drives the run; and
`device_bump/` (CPU unit, host and expected output). Declared totals: 18
rejected and 20 compiled NVPTX cells, 4 CPU cells.

### MATHCK address arithmetic boundary

`./tests/contract/mathck_address_arith.sh` (in `make test`): `^CHAR` +
WORD offsets 40000 and 32768 (either operand order) and ADRMEM + 40000 read
the right element under both settings at O0–O3; the MATHCK+ O0 IR for
`p + n` and `p + (n - 1)` has two non-inbounds GEPs and exactly one overflow
intrinsic (the offset's `-`); `p - 1`, `p * 2`, `p DIV 2`, `2 - p` and
`p + 1.5` are rejected by the typechecker with an exact message and no IR
written; a CINT returned by C `abs` and incremented in Pascal traps under
MATHCK+ and wraps under MATHCK-. Fixtures in `tests/contract/fixtures/mathck`:
`address_word_offset.pas/.out`, `address_c_value.pas` with `_checked.out/.err`
and `_unchecked.out` (the setting is prepended), and `address_gep.pas`, whose
last statement the suite swaps for each rejected operator
(`address_reject.err`). Declared totals: 8 offset, 8 `[C]`, 1 IR, 5 rejection
cells.

### MATHCK diagnostics

`./tests/contract/mathck_diagnostics.sh` (in `make test`) runs one failing
program per MATHCK runtime class at O0/O2: signed and unsigned overflow in a
binary operator, unary minus, `SUCC` and `VSUM`, and signed and unsigned
division by zero. Each prints the `prefix` line, then exactly one
`runtime error: MATHCK <class> in <op> at line L column C (...)` line at the
operator or function-name token. Zero divisors fail under MATHCK- too, and the
overflow cases run to completion there. RANGECK store and SUCC/PRED domain
failures, INDEXCK bounds, INITCK reads and TRUNC failures are run beside them
and must keep their own texts, never the MATHCK stem. RANGECK and INDEXCK
messages are still unlocated; that is RANGECK/INDEXCK work
([contract](../dialect_notes.md#mathck-runtime-diagnostics)).

The fixtures are in `tests/contract/fixtures/mathck`. `diag.pas` holds one failing statement
per stdin case (cases 0–6 MATHCK, 7–10 the other checks), and the suite
prepends either setting. `diag_checked.expected` and `diag_unchecked.expected`
are its exact transcripts, line and column included, so any accidental
renumbering of the source fails. `diag_initck.pas/.err` covers the INITCK
case. The suite also routes every failure: stderr is one line, it matches the
full MATHCK stem for a MATHCK case and never contains `MATHCK` otherwise.
Declared totals: 28 MATHCK, 8 other and 2 INITCK cells.

### MATHCK on/off twins

`./tests/contract/mathck_twins.sh` (in `make test`) checks that MATHCK
changes nothing for a program that never overflows. Every single-file fixture
under `tests/corpus/golden`, `tests/corpus/integration` and `tests/corpus/dialect` is built and run
with `{$MATHCK+}` and with `{$MATHCK-}` written in front of its first line
(line numbers do not move), at O0 and O2: compile status and diagnostics,
exit code, stdout and stderr must be identical. A fixture whose MATHCK+ run
reports a MATHCK error would be counted as overflowing and not compared (its
disabled twin wraps as the contract defines; the suites above pin that);
currently there are none. Link failures are compared by outcome only (the
driver does not link `-lm`, so three fixtures that call libm fail to link at
O0 under either setting). `tests/contract/fixtures/mathck/twin_extended.pas` adds what the
corpus lacks: every extended width, the scoped builtins, the SADDOK family,
VECTOR lanes and reductions and FOR loops ending at each type's maximum, with
results on each type's minimum and maximum; it must print
`twin_extended.out` under both settings at O0-O3. The 16-bit twin
`tests/contract/fixtures/mathck/twin_arith.pas` runs in `mathck_scalar.sh`. The suite runs
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

`./tests/contract/mathck_boundary_values.sh` (in `make test`) runs
`tests/contract/fixtures/mathck/boundary_values.pas` under MATHCK+ and MATHCK- in both
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

`./tests/contract/mathck_optimization.sh` (in `make test`) checks that
optimization never weakens the contract. `tests/contract/fixtures/mathck/fold.pas` emits 9
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
