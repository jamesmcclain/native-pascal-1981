# MATHCK builtin audit

This audit lists every builtin that does integer arithmetic on, or converts, a
user value, and assigns each to MATHCK, RANGECK, a separate contract, or no
check. It applies the approved scope in the [contract record](mathck_contract.md):
MATHCK covers INTEGER/WORD-family `+ - * DIV MOD`, unary minus, SUCC/PRED and
ABS/SQR. Compiler-generated string lengths, index scaling and SUPER extents
stay under their own bounds/descriptor contracts. Conversions such as
TRUNC/ROUND keep separate error contracts. Explicit user arithmetic that
*supplies* a length, position or count is still ordinary MATHCK arithmetic at
its own operators.

Behavior was observed with `bin/pascal1981` on `port-mathck` after the SUCC/PRED,
ABS/SQR and SADDOK-family commits (`20d50ca`, `51dfbc6`, `b093471`). `tests/mathck_builtins.py` pins the
MATHCK-scoped rows and the "no MATHCK check" rows (see the end).

## MATHCK (checked under MATHCK+, wrap under MATHCK-)

| Builtin | Arithmetic | Status |
|---|---|---|
| `SUCC`, `PRED` (integer family) | `v ± 1` at the argument's width | Checked (`overflow in SUCC/PRED`). The domains of CHAR, BOOLEAN, enumerations and subranges are RANGECK's (below). |
| `ABS` (signed) | `0 - v` for a negative `v` | Checked; only MIN overflows (`overflow in ABS`). |
| `ABS` (WORD family) | none | Returns its argument. |
| `SQR` (integer family) | `v * v` | Checked (`overflow in SQR`). |
| `VSUM`, `VPROD` (integer lanes) | left-to-right fold of `+` / `*` | Checked per step (`overflow in VSUM/VPROD`, reporting the partial result and lane); the lane operators follow the scalar rules per lane. VMIN/VMAX cannot overflow. |

A fully constant call must fit its type at compile time under either setting.
A user routine of the same name is an ordinary call.

## Never trapping by definition

| Builtin | Status |
|---|---|
| `SADDOK`, `SMULOK`, `UADDOK`, `UMULOK` | Return the 16-bit "fits" flag and store the wrapped result; never trap (IBM 11-21). |

## RANGECK (domain of the result type)

| Builtin | IBM rule | Status |
|---|---|---|
| `SUCC`, `PRED` on CHAR, BOOLEAN, enumerations, subranges | "error if out of range, caught if $RANGECK on" (11-8) | Checked under RANGECK+ at the call (CHAR/BOOLEAN/enumeration edge, evident subrange bounds). |
| `CHR(x)` | "error if ORD (X) > 255 or ORD (X) < 0 (if $RANGECK on)" (11-8) | **Not checked.** `CHR(300)` is `CHR(44)`; `CHR(-1)` is `CHR(255)`, including a constant `CHR(300)`. This belongs to the recorded "range checks beyond subranges" gap, not to MATHCK. |

## Separate contracts (outside MATHCK)

| Builtin | Why it is outside MATHCK | Status |
|---|---|---|
| `TRUNC`, `ROUND` | REAL-to-integer conversion; IBM checks it unconditionally (11-6) | Always-on range check, independent of MATHCK (G26, §6): a result outside INTEGER or a NaN argument is a located `runtime error`; NVPTX saturates. See `tests/trunc_round_range.py`. |
| `CONCAT` (LSTRING length byte) | Compiler-generated length update under the capacity contract | **No capacity check:** `t: LSTRING(3) := 'ab'; CONCAT(t, 'xyzw')` stores length 6 and overwrites the next variable. Already recorded as an unchecked string capacity gap. |
| `INSERT`, `DELETE`, `COPYLST`, `COPYSTR`, `POSITN`, `SCANEQ`, `SCANNE`, `ENCODE`, `DECODE` | Lengths/positions are compiler-generated (bounds contract); DECODE is a text-to-number conversion | **Unreachable:** codegen lowers them, but the typechecker rejects every call with `Undefined procedure`/`Undefined function`. When enabled, their internal length and position arithmetic (`pos - 1`, `len - pos`) needs capacity and position checks, not MATHCK. |
| `NEW` bounds, `DEVALLOC`, `SIZEOF`, `LOWER`, `UPPER` | Descriptor and layout arithmetic | Under the descriptor/layout contracts (`TypeSizeBytes` rejects layouts above 2147483647 bytes). |
| `READ`/`READLN` of integers | Text conversion | Already checked independently of MATHCK (G29). |

## No check needed (no arithmetic that can overflow, or defined bit operations)

| Builtin | Behavior |
|---|---|
| `ORD` | Same value and width; an enumeration gives its INTEGER32 ordinal. `ORD(WORD)` into INTEGER is rejected (G25). |
| `WRD`, `WRD8` | Bit-pattern conversion: `WRD(-2)` is 65534, as IBM specifies (11-8). |
| `ODD` | Low-bit test. |
| `HIBYTE`, `LOBYTE` | Byte extraction, never above 255. They return CHAR here; IBM returns the argument's type (INTEGER or WORD), a typing difference recorded with the audit, not a MATHCK question. |
| `BYWORD` | Packs the low byte of each operand: `BYWORD(300, -1)` is `11519`. IBM requires operands that fit in one byte; accepting and masking wider operands is a typing difference, not overflow. |
| `FLOAT` | Exact for every INTEGER-family value up to 2^53. The audit found WORD-family values converted as signed (`FLOAT(65535)` was `-1.0`, and so was a mixed REAL operand); fixed in `6cb5622` (see the [WORD audit](word_arithmetic_audit.md)). |
| `RETYPE`, `ADR`, `ADS`, pointer `+` | Reinterpretation and address arithmetic, not MATHCK. |

`FILLC`, `FILLSC`, `MOVEL`, `MOVER`, `MOVESL` and `MOVESR` are not builtins:
the typechecker reports `Undefined procedure`, and the runtime library
defines them under lower-case C names. Their counts are memory-region bounds,
not MATHCK.

## Tests

`tests/mathck_builtins.py` checks the MATHCK rows at every width. The VSUM/VPROD row is checked by `tests/mathck_vector.py`. For the "no
check" rows, it checks that a MATHCK+ program applying ORD, WRD, ODD, HIBYTE,
LOBYTE, BYWORD and FLOAT to extreme INTEGER and WORD variables prints the
defined results above in both dialects at O0–O3 and that its IR contains no
`pas_math_overflow` call. The CHR and CONCAT gaps are recorded here, not
pinned as results.
