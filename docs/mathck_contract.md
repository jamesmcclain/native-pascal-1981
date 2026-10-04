# MATHCK contract and scope decisions

## Status

This is a design decision record for `port-mathck`, not a claim of runtime
protection. The operation scope, enabled overflow definitions, disabled
arithmetic semantics, directive applicability, legacy AST compatibility,
RANGECK interaction, runtime diagnostics and unsupported-boundary policy below
are operator-approved. Implementation gates remain open. At baseline
`e615783`, MATHCK is directive metadata only: the compiler does not emit
arithmetic checks or reject enabled unsupported operations. See
[`../tests/README.md`](../tests/README.md#mathck-gap-baseline) and
`tests/mathck_baseline.json` for the persisted G1–G29 evidence.

Scalar WORD-family DIV/MOD and ordering have since been corrected independently
of MATHCK; G14–G17 and G21 now require correct native output. See the
[WORD arithmetic audit](word_arithmetic_audit.md) for scope and validation.
FOR endpoint termination is also fixed independently of MATHCK. Scalar
DIV/MOD now guard zero divisors unconditionally and sanitize signed MIN/-1:
unchecked DIV returns MIN and MOD returns zero, at every scalar width. Even
constant-dead division instructions have safe divisors. NVPTX scalar DIV/MOD
is rejected because it has no host failure path; CPU-device lowering uses the
host path. VECTOR safety remains open under its separate implementation gate.

The [bootstrap/self-hosting source audit](mathck_bootstrap_audit.md) records
intentional numeric-label key wrapping, wide limit construction and the
explicit ignored-MATHCK pasboot policy. Gen3/gen4 still reach a byte-identical
fixed point. This is not yet a checked-bootstrap guarantee: repeat validation
when operator metadata and enabled arithmetic enforcement ship.

Enforcement status: MATHCK+ scalar `+ - *` is checked at every scalar width
(INTEGER/WORD and the extended 8/32/64-bit types) with LLVM's overflow
intrinsics at the adapted/promoted operand type and signedness, failing
through `pas_math_overflow` before the result is used. The compiler's own
generations 2–4 are built with these checks and still reach the gen3/gen4
fixed point. Signed MIN DIV -1 is likewise checked under MATHCK+ (code
`DIV`), after the mandatory zero-divisor test, and so is unary minus as a
checked `0 - v` (signed MIN overflows; for the WORD family only zero
succeeds), reported with `(operand=…)`. Integer-family SUCC/PRED are checked
steps at the argument's own width (`overflow in SUCC`/`PRED`, with
`(operand=…)` and the builtin name's coordinates). Their CHAR, BOOLEAN,
enumeration and evident subrange domains are checked under RANGECK at the
call, after any base overflow check. Integer ABS and SQR are checked the same
way (`overflow in ABS`/`SQR`): signed ABS overflows only for MIN, a
WORD-family ABS is its argument, and SQR is a checked `v * v`. The IBM
library functions SADDOK/SMULOK/UADDOK/UMULOK never trap: they return the
16-bit overflow flag and store the wrapped result. The
[builtin audit](mathck_builtin_audit.md) classifies every other builtin
that does arithmetic on or converts a user value (CHR is RANGECK and
unchecked; string lengths are capacity contracts). Integer VECTOR lanes
follow the scalar rules per lane, and VSUM/VPROD are checked folds (see
"VECTOR and DEVICE boundaries"). NVPTX DEVICE code rejects enabled checked
operations as `DEVICE arithmetic` boundaries; CPU DEVICE code is checked.

Constant operands: every integer `+ - * DIV MOD` or negation whose value is
fully determined at compile time is folded exactly by the typechecker and
must fit its own type, independently of MATHCK: the integer context's type
when there is one (as for a literal, so `i32 := Base + Step` is 33000 with
INTEGER CONSTs), otherwise the operands' result type. This applies at every
node, so `(M + 1) - 1`, `WRITELN(32767 + 1)`, `WRITELN(-N)` with `N = -32768`
and the operand `M + 1` in `k := i + (M + 1)` are compile-time "integer
constant out of range" errors rather than silent wrapping or a guaranteed
runtime trap. A valid constant operation is tagged with `resolved_type`, and
codegen materializes that exact value at that type instead of re-evaluating
its operands at literal width (`j := i + (M + 1)` with INTEGER32 `j` is
32773). A partially constant operation is checked at run time like any
other. Legacy typed ASTs carry the old reference's BinOp `resolved_type`;
codegen uses it the same way, and an untagged constant operation stays
unchecked.

Operator-site metadata/overflow enforcement remain unimplemented, so MIN DIV
-1 currently wraps under both settings. Mandatory zero errors flush stdout,
print signed/unsigned operands, flush stderr and abort, at the DIV/MOD token's
line and column from the operator snapshot (`line 0 column 0` for a legacy
node without one). Constant zero-divisor rejection and
truncating constant folding remain separate gates; a literal zero division is
currently a deterministic runtime error, not LLVM poison. See the
[scalar safety tests](../tests/README.md#scalar-divmod-safety-prerequisite).

## Approved operation scope

MATHCK governs explicitly evaluated INTEGER-family and WORD-family arithmetic:

| Operation | Scope |
|---|---|
| Binary `+`, `-`, `*` | Arithmetic overflow |
| Binary `DIV`, `MOD` | Division by zero and applicable arithmetic overflow |
| Unary minus | Arithmetic overflow |
| `SUCC`, `PRED` | INTEGER/WORD-family arithmetic endpoints |
| `ABS`, `SQR` | INTEGER/WORD-family arithmetic overflow |

This includes the extended-width scalar integer families (`INTEGER8`,
`INTEGER32`, `INTEGER64`, `WORD8`, `WORD32`, `WORD64`), as well as ordinary
16-bit INTEGER and WORD. The contract is not limited to the first implemented
width. Enabled in-scope operations must eventually either be instrumented or
rejected at compile time; accepting them silently without checks is not a
supported implementation strategy. Wide scalar arithmetic remains an
unsupported boundary until its checks are implemented.

Type admission and promotion are separate from overflow checking; the mixed
INTEGER/WORD decision below closes one such decision gate and is enforced by
the typechecker. SUCC/PRED enumeration/subrange
domain checks remain RANGECK, as specified below; listing these builtins here
does not absorb their domain checks into MATHCK.

### Mixed INTEGER/WORD operand decision (G24)

Reject implicit mixing of nonconstant INTEGER-family and WORD-family operands
in scalar `+ - * DIV MOD`, in either operand order, independently of MATHCK and
in both dialects. This includes signed/unsigned mixtures at extended widths;
there is no unsigned-wins or wider-wins rule that admits such a mixture.
A rejected expression has no arithmetic result type or overflow class.
Same-family width promotion remains unchanged.

Preserve the existing constant-sensitive adaptation exception: an INTEGER
constant may adapt to an admissible WORD context, including the native
16-bit bit-pattern conversion of negative constants. After adaptation, WORD
arithmetic has an unsigned result and unsigned overflow classification.
Nonconstant signed values require an explicit conversion such as `WRD(i)`
for native WORD arithmetic; choosing WORD interpretation must not happen
silently. Neither MATHCK- nor a destination type permits mixed nonconstant
operands. This decision concerns scoped scalar arithmetic, not new rules
for comparisons, assignments, REAL, VECTOR or pointer arithmetic.

This follows IBM §6-5 (manual lines 6144–6147) and §8's same-family arithmetic
rules. **Enforced** in the typechecker's BinOp check (`src/tc_expr.pas`,
`ConstantAdaptsToOperand`): a nonconstant signed/unsigned pair fails with
`Mixed INTEGER-family and WORD-family operands need an explicit conversion
(e.g. WRD) in <op>` before any IR exists. The constant exception is applied
per operand: an INTEGER-family constant adapts to a WORD-family operand at
every width (negative values by bit pattern, as at 16 bits), and a WORD-family
constant mixes with a signed operand only when its value fits that operand's
type, so `i + 40000` is rejected rather than computed with a type the
typechecker and codegen disagreed on. `tests/mathck_mixed_width.py` covers
both operand orders, all five operators, every signed/unsigned width pair,
both settings, explicit `WRD` conversion and the preserved constant
adaptation; the G24 baseline probe is a `correct-reject`.

Same-family operands of different widths widen to the wider operand, which
is the result type and the checked width (`INTEGER32 * INTEGER` is checked
at 32 bits); the same test pins this for every ordered width pair.

### ORD(WORD) conversion decision (G25): defer

Defer the adjacent IBM-compatible `ORD(WORD)` conversion fix; it does not block
MATHCK metadata or arithmetic instrumentation. Until separately implemented,
integer-family arguments to ORD retain their argument type, width, signedness
and value, as in the current typechecker/codegen. Thus ORD of a native WORD
is still WORD, not a back door around the mixed-operand rule. Assigning that
result to native INTEGER remains an implicit-narrowing error. This temporary
behavior is an explicit compatibility gap, not a ratification of IBM parity.

IBM §11-6/7 (manual lines 11896–11908) instead returns INTEGER with the same
16-bit pattern: WORD arguments `32767`, `32768` and `65535` yield INTEGER
results `32767`, `-32768` and `-1`, respectively. Native `-32768` is valid data, so a future same-pattern
conversion must not trap merely for producing it. ORD is a conversion, not
an in-scope MATHCK arithmetic operator; changing MATHCK must not change its
conversion semantics.

G25 stays a known-gap rejection. A separate conversion slice must decide the
extended WORD-family result types, update typechecker and codegen together,
audit bootstrap/pasboot dependencies, and test low/high-bit boundaries and
subsequent arithmetic/assignment before changing the current behavior. No
new wide conversion contract or implementation is claimed here.

### FOR stepping

FOR-loop control must terminate at the final value without stepping past it.
This is an unconditional arithmetic-correctness requirement, independent of
MATHCK: enabling MATHCK must not turn a naturally terminating loop into an
overflow error, and disabling it must not allow endpoint wraparound to make
the loop infinite. Explicit arithmetic in bounds or the body remains in the
ordinary operation scope above.

### Compiler-generated bookkeeping

Implicit string-length arithmetic, index scaling, and SUPER extent/descriptor
calculations remain under their existing INDEXCK, RANGECK, allocation and
descriptor contracts. They do not acquire MATHCK guards merely because the
compiler emits arithmetic instructions for them. This exclusion neither
weakens those contracts nor excuses overflow or LLVM undefined behavior in
compiler-generated calculations. Explicit in-scope arithmetic in a user
expression supplying a length, index, or extent is still subject to MATHCK.

### REAL arithmetic and conversions

REAL arithmetic is outside MATHCK. Conversion errors, including TRUNC/ROUND
range failures, retain separate error contracts independent of MATHCK.

**REAL arithmetic (G27), recorded explicitly in §6: out of scope.** REAL and
REAL32 `+ - * /`, unary minus, and REAL ABS/SQR/SQRT/LN/EXP follow IEEE 754
under either MATHCK setting: overflow gives `INF`/`-INF`, `x / 0.0` gives a
signed infinity, and `0.0 / 0.0` or `INF - INF` gives a NaN (whose printed
sign follows the platform, `-NAN` on x86-64). Nothing traps, and MATHCK
neither adds nor removes a REAL check. IBM's REAL error reporting (its REAL
functions "always check", 11-8, through the real-math library rather than
MATHCK) is not reproduced. Any future REAL checking (overflow, invalid
operation, division by zero) needs its own directive decision and must not
be smuggled into MATHCK. The G27 and G27.overflow baseline probes pin `INF`
and `-INF` under MATHCK+ as `out-of-scope-output`.

**TRUNC/ROUND (G26), decided and implemented in §6: a separate, always-on
check.** IBM ties it to no directive (11-6: "Error if ABS(X) > MAXINT"), so
neither MATHCK- nor RANGECK- disables it. A result outside INTEGER's
`-32768..32767`, or a NaN argument, fails before the conversion with
`runtime error: TRUNC result out of INTEGER range at line L column C
(value=V)` (or `ROUND`), at the function name's coordinates (`op_location`
from the parser, with no MATHCK snapshot), after flushing stdout
(`pas_conversion_error` in `runtime/numeric.c`; `CodegenCheckedRealToInt` in
`src/cg_expr.pas`). The ordered compares that guard `fptosi` also reject NaN,
so no out-of-range conversion reaches LLVM poison. NVPTX DEVICE code has no
host failure path and uses `llvm.fptosi.sat` (saturating; NaN gives 0)
instead: defined, but not IBM's error, and recorded as a device gap. CPU
DEVICE code takes the host failure path. `tests/trunc_round_range.py` pins
all of this; the G26 baseline probes are `correct-runtime-error`.

### Address arithmetic and [C] code (recorded in §6)

Pointer and ADRMEM `+` an integer offset is address arithmetic, not MATHCK:
it lowers to a non-inbounds GEP scaled by the pointee size (bytes for
ADRMEM), which wraps in the address space without LLVM undefined behavior
and never traps, under either setting. The offset is widened to 64 bits by
its own signedness (a literal from its exact value), so a WORD offset of
40000 addresses element 40000; before §6 a 16-bit GEP index was read as
signed and such offsets went backwards. Arithmetic *inside* an offset
expression (`p + (n - 1)`) is ordinary MATHCK arithmetic at its own operator.
Only `pointer + integer` (either order) is admitted; `p - n`, `p * n`,
`p DIV n` and a REAL offset are typecheck errors (`Pointer arithmetic
supports only pointer + integer offset`) instead of unlocated codegen
aborts. Pointer validity is the NILCK/INDEXCK/descriptor contracts' concern,
not MATHCK's.

Arithmetic performed inside a `[C]` (or other EXTERN) routine is outside
MATHCK: the compiler never sees it. A value a `[C]` routine returns, of
CINT/CLONG/CSIZE_T or any integer type, is ordinary data once it reaches
Pascal: Pascal arithmetic on it is checked at its own type (CINT `+` is
INTEGER32 arithmetic). `tests/mathck_address_arith.py` pins these rules.

### VECTOR and DEVICE boundaries

Enabled INTEGER/WORD-family arithmetic in VECTOR operations or DEVICE code
must be rejected at unsupported boundaries rather than silently claiming
protection. This applies to in-scope arithmetic, not simply to declaring a
vector or compiling DEVICE code, and does not bring REAL arithmetic into
MATHCK. The rejection policy and diagnostic categories are specified below;
their implementation is not added by this documentation-only decision.

**VECTOR: implemented as per-lane checks (§6), so `VECTOR arithmetic` is no
longer a boundary.** Under the operation's MATHCK+ snapshot, integer lane
`+ - *` and unary minus compute every lane with one vector overflow
intrinsic and branch once on the OR of the overflow lanes; only on failure
does a cold path redo the operation one lane at a time, in lane order,
through the scalar checked paths (`CodegenLanewiseIntOp` and
`CodegenLanesIntOp` in `src/cg_expr.pas`, §8 optimization). The lowest
failing lane reports its own operands with the scalar diagnostic at the
operator's coordinates. Lane DIV/MOD are always lowered that way through
the scalar safe division, under either setting, so a zero lane fails with the
zero-divisor diagnostic and signed MIN/-1 is MIN (DIV, MATHCK-), an overflow
(DIV, MATHCK+) or 0 (MOD); no vector division instruction is emitted. Integer
VSUM/VPROD carry a snapshot at the function name and, under MATHCK+, are a
left-to-right fold of checked steps reporting `overflow in VSUM` (or `VPROD`)
with the partial result and lane (`CodegenCheckedVReduce`). MATHCK- lane
`+ - *`, negation and reductions keep the wrapping SIMD instructions. REAL
lanes are unchanged; VMIN/VMAX cannot overflow. VECTOR is rejected on NVPTX
altogether, so only host and CPU-device code reaches these paths.
`tests/mathck_vector.py` covers every integer element type.

**DEVICE: decided and implemented in §6 as a host-only policy with the
`DEVICE arithmetic` boundary on NVPTX.** NVPTX code has no host failure path,
and a device-side error channel (state in device memory, transport across
LAUNCH, a non-trapping way to stop the failing thread) is not planned, as for
INITCK. An operation the operation's MATHCK+ snapshot would check there
(`+ - * DIV MOD`, unary minus, SUCC/PRED, signed ABS, SQR; not a fully
constant fold, not WORD ABS) is rejected before any IR is published with
`MATHCK unsupported boundary: DEVICE arithmetic at line L column C`
(`MathckDeviceBoundary` in `src/cg_expr.pas`, at the operator or function
name). MATHCK- at the operation is the opt-out and wraps; DIV/MOD stay
rejected on NVPTX under MATHCK- as well, because the mandatory zero-divisor
failure has no device path either. Because MATHCK defaults on, existing NVPTX
kernels with integer arithmetic must add `{$MATHCK-}` (the repository's own
NVPTX fixtures and `tests/gpu` kernels now do). Unlike INITCK, which keys its
boundary on every DEVICE compiland, MATHCK keys it on NVPTX only: CPU DEVICE
code links the host runtime, so `pas_math_overflow` works there and its
kernels are checked through LAUNCH exactly like host code. VECTOR is already
rejected on NVPTX. The SUCC/PRED RANGECK domain checks remain skipped on
NVPTX (RANGECK's own open DEVICE decision). `tests/mathck_device.py` pins
the NVPTX matrix (exact diagnostics, no IR, MATHCK- twins, unchecked
operations) and CPU DEVICE trapping/wrapping.

## Approved enabled overflow definition

For an in-scope operation with MATHCK enabled, overflow means that its exact
mathematical result is outside the result type's actual native range. Use the
resolved result type, including its width and signedness; do not infer the
range from the destination of a later assignment. Type admission, promotion
and store-time subrange checks remain separate decisions/contracts.

For a signed N-bit integer the range is `-2^(N-1)..2^(N-1)-1`; for an unsigned
N-bit word it is `0..2^N-1`. This rule applies uniformly to the supported scalar
widths (8, 16, 32 and 64 bits), including extended types. It is a mathematical
definition, not a requirement to compute the exact result in a same-width
machine integer before checking it.

### INTEGER minimum is ordinary data

Native INTEGER is `-32768..32767`. There is no reserved `#8000` result, sentinel
exception, or separate MATHCK range. In particular, `-32767 - 1`,
`-16384 * 2`, and `PRED(-32767)` produce valid `-32768` without overflow.
`32767 + 1`, unary minus of `-32768`, and `ABS(-32768)` overflow. The same
endpoint rules apply at every signed width.

### WORD unary minus

Unary minus uses the exact mathematical result: negating unsigned zero
succeeds, while negating any nonzero WORD-family value overflows under
MATHCK+. There is no IBM-style compile-time warning merely for using unary
minus on WORD. This deliberately diverges from IBM's always-warning rule;
the enabled overflow check supplies the protection. It does not suppress
ordinary compile-time constant-range errors. Disabled negation is defined
below.

### DIV and MOD endpoints

Division uses truncation toward zero; the remainder has the dividend's sign.
A zero divisor is a division-by-zero error, not a representability test.
For signed MIN and divisor `-1`, DIV's exact quotient is outside the signed
range and therefore overflows under MATHCK+. MOD's exact remainder is zero,
which is representable, so it succeeds without an overflow error. MOD must
not inherit a trap solely because a machine quotient would overflow. Neither
operation may execute LLVM undefined behavior to obtain its result.

### Other scoped arithmetic

Apply the same exact-result rule to binary addition, subtraction and
multiplication, SUCC/PRED, ABS and SQR. Unsigned subtraction below zero and
unsigned addition/multiplication above the maximum overflow. SUCC of the
base-type maximum and PRED of its minimum overflow; ABS of the signed minimum
and a nonrepresentable square overflow. A representable result does not
overflow merely because it equals a historical IBM invalid value.

These definitions are approved design, not implemented checks. Runtime
failure reporting follows the approved diagnostics below.

## Approved MATHCK- semantics

Disabling MATHCK disables representability traps for in-scope scalar arithmetic;
it does not license LLVM undefined behavior or optimization-dependent results.
The same resolved result width and signedness apply as with checking enabled.

### Wrapping arithmetic

Binary `+`, `-`, `*`, unary minus, SUCC/PRED, ABS and SQR wrap at the result
width. Retain the low N bits of the exact result (modulo `2^N`), interpreted
as the result type: unsigned for WORD-family types and two's-complement signed
for INTEGER-family types. This is defined behavior at every scalar width.
For example, disabled INTEGER `32767 + 1` is `-32768`, ABS of INTEGER
`-32768` remains `-32768`, and WORD unary minus of `1` is `65535`.

### Defined division and remainder

- DIV or MOD with a zero divisor always fails deterministically, even with
  MATHCK disabled. It is a runtime error, not an unhandled machine exception
  or a fabricated numeric result. Use the approved runtime diagnostics below.
- Signed `MIN DIV -1` returns MIN with MATHCK disabled. Signed `MIN MOD -1`
  returns zero, with either setting. Handle these endpoints without executing
  an overflowing LLVM signed divide or remainder instruction.
- Other signed DIV/MOD use truncation toward zero and a remainder with the
  dividend's sign; WORD-family DIV/MOD use unsigned arithmetic.

Zero-divisor failure and these endpoint results must be independent of the
optimization level. A constant zero divisor must be diagnosed at compile time,
not lowered into LLVM UB. Disabling MATHCK does not relax ordinary compile-time
constant-range/type errors, store-time RANGECK contracts, conversion errors,
or the unconditional requirement that FOR stepping terminate at its endpoint.

### Difference from IBM and implementation status

These disabled results are a deliberate defined native contract, not an
attempt to reproduce IBM's undefined disabled ABS/SQR results or
optimization-dependent overflow traps. IBM's statement that disabling MATHCK
does not always disable checking is compatible with retaining zero-divisor
errors; it does not define the native wrapping endpoint policy.

This documentation does not implement the rules. In particular, the baseline
compiler still emits LLVM UB for zero divisors and signed MIN/-1 endpoints,
and its WORD division still uses signed instructions. The existing compile-only
and crash-class gap probes remain unchanged until the corresponding fixes can
replace them with defined-result/error oracles.

## Approved directive applicability

Each in-scope source operation uses the effective MATHCK setting at its own
source token, not at the end of its expression, at an assignment destination,
or at a routine declaration or invocation elsewhere.

- Binary arithmetic snapshots the `+`, `-`, `*`, `DIV` or `MOD` token.
- Unary minus snapshots its unary `-` token.
- Scoped builtin calls (SUCC, PRED, ABS, SQR) snapshot the function-name token,
  not the opening parenthesis, argument tokens or closing parenthesis.

Capture the token's setting before advancing past it. Parsing the right operand
or argument list must not substitute a later token's flags. Each nested source
operation has its own independent snapshot; a builtin's setting does not
replace the settings of arithmetic inside its arguments. Ordinary user-defined
calls do not impose the caller's MATHCK setting on operations in the callee.

For example, with MATHCK initially enabled:

```pascal
x := a + {$MATHCK-} b;       { + remains checked }
x := a {$MATHCK+} + b;       { this + is checked }
x := ABS({$MATHCK-} a + b);  { ABS checked; argument + unchecked }
```

Use the existing directive machinery to determine the effective token setting:
MATHCK defaults to enabled; DEBUG coupling, subsequent explicit overrides,
PUSH/POP, numeric directive forms, conditional compilation and includes all
apply. Include-file tokens carry their effective lexical setting just like
other source tokens. Conditional compilation determines the active token
stream; the parser must not reconstruct settings from skipped source text.
A directive after a snapshot affects subsequent tokens only, even when it
occurs inside the same expression or argument list.

The snapshot is per operation, not a dynamic runtime flag. It must survive
parsing and typechecking unchanged so codegen can honor the approved enabled
or disabled behavior at that operation. Legacy nodes without a snapshot follow
the policy below.

Implementation: the parser adds `mathck` (BOOLEAN) and `op_location`
(`{line, column}`) to BinOp `PLUS`/`MINUS`/`MUL`/`DIV`/`MOD`, to the
sign-minus UnaryOp, and to FuncCall nodes named SUCC/PRED/ABS/SQR. The
snapshot is syntactic (set, REAL and CHAR uses carry it too); applicability
is decided by later stages. The typechecker annotates nodes in place and
never rebuilds them. Codegen reads an operation's metadata only from that
operation's node: the DIV/MOD zero-divisor diagnostic and the checked
`+ - *` lowering consume `op_location`, and checked `+ - *` consumes
`mathck`. Never read `mathck` from another node or a flags object: cJSON key
lookup ignores case, so a flags object's `MATHCK` entry would match.

## Approved legacy AST compatibility

A BinOp, UnaryOp or scoped FuncCall without a MATHCK snapshot is a legacy
unchecked operation. Absence does not mean the current source default, an
enclosing node's setting, or a request to reconstruct directive state. Do not
synthesize an enabled snapshot merely because MATHCK defaults to enabled for
new source tokens. This rule is per node: an unchecked parent does not erase
an explicit snapshot on a nested operation.

Legacy unchecked operations obey the approved MATHCK- semantics, including
wrapping representability overflow, deterministic DIV/MOD zero-divisor errors,
and defined signed MIN/-1 results. Unchecked does not mean unsafe LLVM lowering.

Keep the frozen AST files in `tests/reference/` unchanged and preserve their
existing valid-program outputs. Adding new snapshot metadata to newly parsed
source does not justify rewriting frozen inputs to opt them into checking.
Compatibility does not preserve UB-derived values, crashes or optimization-level
differences: such probes must move to the defined disabled-result/error contract
when their lowering is fixed, not become frozen output guarantees.

Here **UB** means **undefined behavior**: an operation for which LLVM provides
no valid-result guarantee. Integer division by zero and overflowing signed
MIN/-1 division/remainder are relevant examples. Optimizations can turn such
operations into arbitrary results or crashes; historical observations are not
a language contract.

This is a documentation-only compatibility decision. Legacy handling and safe
arithmetic lowering still require implementation and regression tests; no frozen
AST files or baseline expectations are changed by this commit.

## Approved interaction with RANGECK

MATHCK checks representability of an in-scope arithmetic operation in its
resolved base result type. RANGECK retains domain and destination constraints;
a narrower destination does not redefine the arithmetic operation's overflow
range.

- Store-time subrange checks (`EmitSubrangeCheck`) remain RANGECK checks.
- SUCC/PRED bounds for enumeration and subrange domains belong to RANGECK.
  INTEGER/WORD-family base-type endpoint overflow belongs to MATHCK. For a
  numeric subrange operation to which both constraints apply, the base-type
  representability and the subrange-domain constraint are distinct checks.
  Enumeration domain checking does not itself bring enum arithmetic into
  MATHCK's INTEGER/WORD-family scope.
- Each switch controls its own checks. MATHCK- does not disable RANGECK, and
  RANGECK- does not disable MATHCK or mandatory zero-divisor errors. Disabled
  base arithmetic follows the approved wrapping/division rules rather than
  borrowing protection from RANGECK.

When both checks apply, check base-type arithmetic overflow first, then the
applicable domain/store range. A MATHCK failure terminates before a RANGECK
check can consume a failed arithmetic result. If arithmetic succeeds but the
result violates an enabled domain or destination check, report RANGECK.
Neither failure may publish the failed result to a destination or allow its
use by subsequent user computation. This ordering concerns checks on the same
result, not a change to operand evaluation or unrelated checks.

For example, INTEGER `32767 + 1` overflows under MATHCK+ before any assignment
subrange check. An INTEGER addition yielding `11` is representable, but storing
it in `0..10` fails under RANGECK+. SUCC of `10` in that subrange is a domain
failure under RANGECK+, not base INTEGER overflow. At an endpoint shared by a
numeric subrange and its INTEGER/WORD base type, an enabled base overflow check
wins before an enabled domain check.

This is a documentation-only ordering and ownership decision. Runtime guards,
SUCC/PRED domain enforcement and combined-check regression tests remain
implementation work; existing RANGECK code is not changed here.

Implemented for SUCC/PRED: under RANGECK+ (the statement's setting, like
store checks), stepping a CHAR, BOOLEAN or enumeration value past its first
or last ordinal fails before the step, and a result outside the declared
bounds of a subrange argument whose type is evident at the call (a variable,
designator or nested SUCC/PRED) fails after it. Both use the existing
`runtime error: value V is outside subrange LO..HI` diagnostic. A subrange
value reaching SUCC/PRED any other way (for example a function result) is
stepped in its host type and checked where it is stored. A shared endpoint
reports MATHCK's base overflow first.

## Approved runtime diagnostics

An arithmetic failure emits one line on stderr with this message stem:

```text
runtime error: MATHCK <class> in <operator> at line L column C
```

The class is one of `signed overflow`, `unsigned overflow`, `signed division
by zero`, or `unsigned division by zero`, according to the resolved arithmetic
type. Use the source operator spelling (`+`, `-`, `*`, `DIV`, `MOD`) or uppercase
builtin name (`SUCC`, `PRED`, `ABS`, `SQR`). The coordinates identify the
operator token or builtin function-name token used for the directive snapshot,
not the destination or the end of the expression.

Include already-evaluated operands in the same line, without evaluating any
source expression again. Report original operand values, not a wrapped result
or a fabricated quotient, and format them according to their signedness and
width. Operand reporting must not introduce side effects or expose LLVM UB.
The stem above specifies the class/operator/location structure. As
implemented, binary operators and the VECTOR reductions append
`(left=L, right=R)` (for `VSUM`/`VPROD`, the partial result and the lane) and
unary minus and the scoped builtins append `(operand=X)`; builtin names are
`SUCC`, `PRED`, `ABS`, `SQR`, `VSUM`, `VPROD`.

Implemented and pinned: `tests/mathck_diagnostics.py` checks one program per
class at O0/O2 for the exact single line, the flushed stdout prefix and the
token coordinates, and that RANGECK (store and SUCC/PRED domain), INDEXCK,
INITCK and TRUNC/ROUND failures keep their own texts and never use the MATHCK
stem. The per-operation suites pin the same texts across widths and O0-O3.

**RANGECK and INDEXCK messages stay unlocated (decided for MATHCK §7).**
SUCC/PRED domain failures use the RANGECK text `value V is outside subrange
LO..HI`, with no coordinates and the word "subrange" even for CHAR, BOOLEAN
and enumeration domains. Adding coordinates or domain-specific wording means
changing the `pas_subrange_error` runtime interface and every store-check
caller, which is RANGECK's own open diagnostics work (located RANGECK
classes, file/include identity, runtime ABI compatibility). MATHCK does not
change it; the RANGECK record owns that decision.

Failure handling follows the existing `runtime/subrange.c` and
`runtime/array_index.c` convention:

1. Flush stdout so prior output is not lost on failure.
2. Print the single diagnostic line to stderr and flush stderr.
3. Call `abort()` before the failed result can be stored or used.

This applies to mandatory zero-divisor errors under MATHCK- as well as failures
under MATHCK+. Tests should require failure and the exact diagnostic, not a
platform-specific signal number or exit status. Do not add a second error line
or print IBM error numbers in the runtime message.

For historical reference only, the error classes map to IBM Appendix A as
follows:

| Native class | IBM number | IBM name |
|---|---|---|
| unsigned division by zero | 2051 | Unsigned Divide By Zero |
| signed division by zero | 2052 | Signed Divide By Zero |
| unsigned overflow | 2053 | Unsigned Math Overflow |
| signed overflow | 2054 | Signed Math Overflow |

The mapping is descriptive, not an adoption of IBM's INTEGER sentinel/range
rules. Compile-time constant errors and unsupported-boundary diagnostics are
separate from this runtime format. This documentation-only decision implements
no runtime helper or guards; located exact-text and flushed-prefix tests remain
implementation work.

## Approved unsupported-boundary policy

An enabled, in-scope operation for which checks are not implemented is a hard
compile-time error, not a warning or silent unchecked acceptance. Emit a located
diagnostic in this form:

```text
MATHCK unsupported boundary: <category> at line L column C
```

Use the operation's operator/function-name token coordinates, as for its MATHCK
snapshot. The diagnostic categories are:

| Category | Unsupported enabled operation |
|---|---|
| `scalar arithmetic` | ordinary INTEGER/WORD scalar operation lacking its checks |
| `wide arithmetic` | extended-width scalar integer-family operation lacking its checks |
| `VECTOR arithmetic` | in-scope integer-family vector operation lacking its checks |
| `DEVICE arithmetic` | in-scope integer-family operation in DEVICE code lacking its checks |

Reject before publishing IR. Do not replace this error with a one-time lexer
warning: simply enabling MATHCK is silent if no unsupported in-scope operation
is encountered. Declarations and operations outside MATHCK's scope do not
trigger this diagnostic merely because the directive is enabled. A category
ceases to be a boundary for a particular operation when its checks are supported;
this policy is not a permanent ban on wide, VECTOR or DEVICE arithmetic.

MATHCK- at the operation is the checking opt-out; a legacy node without a
snapshot is likewise unchecked under the approved legacy policy. Neither route
permits unsafe arithmetic: defined wrapping, zero-divisor failure and safe
MIN/-1 handling still apply where those operations are admitted. Opting out
of MATHCK does not relax other type, target, range or descriptor constraints.

This is a documentation-only policy decision. No boundary detection or
rejection is implemented here. In particular, the baseline's silently accepted
enabled scalar arithmetic remains a gap, not newly supported behavior. Tests
for exact diagnostics, located operations and empty IR remain implementation
work; the gap baseline is unchanged.
