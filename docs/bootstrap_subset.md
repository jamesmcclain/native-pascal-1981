# The bootstrap subset

Generation 1 of the compiler is built by `bootstrap/pasboot`, a small C99
program in this tree. `pasboot` translates one Pascal compiland to one C
translation unit, and `clang` compiles it. No other Pascal compiler, and no
Python, takes part in `make bootstrap`.

`pasboot` accepts only a narrow part of the extended dialect: the part that
the generation-1 sources use. This document defines that part. It is a
contract. A change to a generation-1 source must stay inside it, or the
bootstrap fails.

- [Subset scope](#which-files-the-subset-applies-to)
- [Accepted forms](#what-the-subset-contains) and [exclusions](#what-the-subset-leaves-out)
- [Semantics](#semantics)
- [Self-hosting arithmetic](#self-hosting-arithmetic) and [hardening limits](#arithmetic-hardening-limits)
- [C organization](#how-the-c-is-organized) and [tests](#how-the-subset-is-tested)

## Which files the subset applies to

The subset applies to the 29 compilands that generation 1 compiles, and to
the `.inc` interfaces that they splice:

- `jsonutil`, `argparse`, `features`
- the parser units `ps_base`, `ps_expr`, `ps_stmt`, `ps_decl`
- the typechecker units `tc_base`, `tc_types`, `tc_expr`, `tc_stmt`,
  `tc_decl`
- the code generator units `cg_base`, `cg_util`, `cg_types`, `cg_symbols`,
  `cg_expr_shape`, `cg_expr_sets`, `cg_expr_support`, `cg_expr_literals`,
  `cg_expr_vector`, `cg_expr`, `cg_io`, `cg_stmt`, `cg_decl`
- the stage programs `lexer`, `parser`, `typechecker`, `codegen`

The unit lists are in `scripts/build-stage.sh` and in the `*_UNITS`
variables of the `Makefile`. `driver.pas`, `proxy.pas`, `pretty81.pas`,
`astcompare.pas`, `sysutil.pas`, and the proxy support units are not in this
set. The finished (generation 4) compiler builds them, so they can use the
full dialect.

Run `tests/check/bootstrap_subset.sh` to check these files. It runs
`pasboot --parse-only` on each compiland. `make test` and `make test-quick`
run it too.

## What the subset contains

| Area | Contents |
| --- | --- |
| Compilands | `PROGRAM p(input, output)`; `IMPLEMENTATION OF u` after its spliced `INTERFACE; UNIT u [(exports)]; ... END;`; `USES`; `(*$INCLUDE:'x.inc'*)` or `{$INCLUDE:'x.inc'}`; ignored `$MATHCK+`, `$MATHCK-`, `$MATHCK:<signed integer>` |
| Declarations | `CONST`, `TYPE`, and `VAR` sections, at file scope and in routines. A constant is a literal, a named constant, or `+ - * DIV` and unary minus on those. |
| Routines | `PROCEDURE` and `FUNCTION` at file scope only; `FORWARD`; `[C]` in an interface; `[C]; EXTERN;` in an implementation or program |
| Parameters | value and `VAR`, in groups (`a, b: ADRMEM`) |
| Types | `INTEGER` (16 bits), `INTEGER32`, `INTEGER64`, `CINT`, `CLONG`, `CSIZE_T`, `REAL`, `BOOLEAN`, `CHAR`, `ADRMEM`; `LSTRING(n)`; `ARRAY [lo..hi] OF T` with constant bounds; `RECORD` without variants; `^T`; enumerations |
| Statements | assignment, procedure call, compound, `IF`/`ELSE`, `WHILE`, `FOR ... TO` and `DOWNTO`, `RETURN`, `BREAK`, `CYCLE` |
| Operators | `+ - * / DIV MOD`, `= <> < <= > >=`, `AND OR NOT`, unary `-`, `AND THEN` in an `IF` or `WHILE` condition |
| Builtins | `CONCAT(dest, src)`, `ORD`, `CHR`, `RETYPE`, `SIZEOF`, `ADR <identifier>`, `TRUNC`, `WRITE` and `WRITELN` |
| Predefined constants | `TRUE`, `FALSE`, `NIL`, `MAXINT`, `MAXWORD`, `MAXINT32`, `MAXINT64` |

Some forms have more limits:

- `WRITE` and `WRITELN` take only string literals and `CHAR` values. They
  take no file argument, no `:width`, and no `:precision`.
- The destination of `CONCAT` is a bare `LSTRING` variable. The source is an
  `LSTRING` value or a string literal.
- `ADR` takes a bare identifier.
- `RETYPE` converts between integer types, or between pointer types.
- A `[C]` routine has scalar parameters and a scalar result only:
  `ADRMEM`, a typed pointer, an integer type, or `REAL`.

## What the subset leaves out

`pasboot` rejects each of these constructs with the message
`file:line: unsupported: <construct>`:

- `SET` types, set constructors, and `IN`
- `CASE`, `REPEAT`/`UNTIL`, `WITH`, `GOTO`, `LABEL`, and labeled statements
- `PACKED`, record variant parts, and named subrange types
- multi-dimensional arrays and `a[i, j]`; `SUPER ARRAY`; `VECTOR`
- `ADS` and `ADR OF`; `FILE OF`, `TEXT`, and all file input and output
- `STRING(n)`
- every string intrinsic except `CONCAT`, and every other builtin function
- `XOR` and `OR ELSE`
- `VARS`, `CONST`, and `CONSTS` parameters, and procedural parameters
- routine attributes other than `[C]`, and variable attributes
- nested routines
- `MODULE` and `DEVICE` compilands
- every metacommand except `$INCLUDE` and standalone `$MATHCK` settings

To widen the subset, change `bootstrap/parse.c` or `bootstrap/emit.c`, add a
fixture in `tests/unit/pasboot/`, and update this document.

## Semantics

`pasboot` gives the subset the meaning that the native compiler gives it.
These rules are the ones that a C programmer does not expect:

- `INTEGER` is 16 bits. An operation on two integer operands is done at the
  width of the wider operand, and the result wraps at that width. The C is
  compiled with `-fwrapv`. `$MATHCK` settings are accepted but deliberately
  ignored: generation 1 uses unchecked arithmetic, even under `$MATHCK+`.
  This is the native MATHCK- wrapping policy, not a claim of enabled checks.
  Malformed settings are rejected. No DEBUG coupling or PUSH/POP processing
  is added to pasboot; those metacommands remain outside the subset.
  See [self-hosting arithmetic](#self-hosting-arithmetic).
- All integer comparisons are signed. `CHAR` comparisons are signed too.
- `AND` and `OR` evaluate both operands. Only `AND THEN` stops early.
- `/` always gives a `REAL`. An integer operand converts to `REAL` when the
  other operand is a `REAL`.
- `ORD` of a `CHAR` zero-extends it to a 16-bit `INTEGER`. `ORD` of an
  integer keeps its value and width, and `ORD` of an enumeration value gives
  an `INTEGER32`. `CHR` keeps the low 8 bits.
- `RETYPE` between integer types keeps the low bytes when it narrows, and
  sign-extends when it widens.
- `TRUNC` gives a 16-bit `INTEGER`.
- A `FOR` loop evaluates its limit one time. After the loop, the control
  variable is one step past the limit. A limit at the maximum of its type
  stops the loop. Native FOR exits at the final value without stepping
  past it; the post-loop value is undefined. Compiler sources do not depend
  on pasboot's one-past value.
- An `LSTRING` keeps its length in element 0. Comparison of two strings
  compares the common length with `memcmp`, and then the lengths.
- `pointer + integer` moves by the size of the pointed-to type. For
  `ADRMEM` and `^CHAR`, that is one byte. All pointer types can be assigned
  to each other.
- A function name on the left of `:=` sets the result. A function name in an
  expression is a call, also inside the same function.

Where the Python reference compiler and the native compiler differ,
`pasboot` follows the native compiler. There are two such differences: the
Python compiler evaluates a `FOR` limit again on each iteration, and its
`RETYPE` fills with zeros when it widens. The generation-1 sources do not
depend on either rule.

## Self-hosting arithmetic

Native compiler generations use operator-site MATHCK checks; pasboot accepts
but ignores the setting. This distinction is intentional, not evidence that
native overflow protection is pending. The [native contract](dialect_notes.md#mathck-integer-overflow-and-division-checks-both)
defines user arithmetic; this section describes compiler-source dependencies.
The 29 generation-1 compilands listed above and ten finished-compiler tools
make up the 39 Pascal compilands under `src/`. Shared `.inc` declarations are
part of their interfaces. `runtime/` contains C, not Pascal: these rules do
not turn its arithmetic into MATHCK operations.

### Intentional wrapping and explicit overflow detection

`ps_base:StrToIntVal` converts numeric LABEL/GOTO/statement labels to low
16-bit equality keys: 32767, 32768, 40000 and 65535 map to 32767, -32768,
-25536 and -1. Declarations, definitions and references use the same converter.
Only accumulator `val * 10 + digit` (including the safe 0..9 digit subtraction)
and sign conversion `-val` run under local MATHCK-; each restores MATHCK+
immediately. The loop increment and following routines stay enabled. This is
not general integer-literal conversion, approval of aliases outside the native
16-bit label domain, or a change to label grammar/range policy.

The `FoldArith` helpers in `tc_expr` and `cg_types` also use local MATHCK-:
they compute wrapped INTEGER64 `+ - *` and negation, restore MATHCK+, and test
whether the exact result fits. This prevents a user's overflowing constant
from trapping the checked compiler itself. The typechecker records overflow
for its constant diagnostic; codegen does not fold an overflowing legacy AST.
These helpers are explicit overflow detection, not permission to accept a
wrapped constant as an exact mathematical result.

No compiler hash/checksum requires arithmetic overflow. Normal counters,
allocation sizes and numeric values must not use MATHCK- to hide exhaustion.
There is no unit-wide or program-wide opt-out.

### Wide limits, WORD and division

- `tc_expr:MaxWord16Value` and `cg_decl:ConstIntegerType` construct 65535
  from an INTEGER64 variable, `32767 * 2 + 1`; destination adaptation must
  not be used to excuse overflowing narrow intermediate operations.
- `tc_expr:MaxInteger32Value` and `cg_decl:MaxConstInteger32` compute
  `32767^2 * 2 + 4 * 32767 + 1 = 2147483647` in INTEGER64. All intermediates
  fit, as does the WORD32 limit `2147483647 * 2 + 1 = 4294967295`.
- `cg_types:SuperElementSize` constructs its CLONG limit as
  `(2^31-1)*2^32 + (2^32-1) = 2^63-1`; multiply/add fit signed 64 bits.
  Its size/divisibility guards are not modular arithmetic. Predefined maxima
  in `tc_base` are literals. RETYPE narrowing, CHR truncation and LLVM bit
  constants are representation conversions, not arithmetic-wrap exemptions.
- Compiler Pascal variables/formals do not use WORD-family types; WORD names
  describe user types, limits and lowering. Array/set bounds are signed
  INTEGER32 or wider host values: 65535 is positive, unlike its label key.
  [Unsigned scalar/FOR ordering and division](dialect_notes.md#word-arithmetic-and-comparison-boundaries) need
  no signed-WORD workaround. Widened i128 bounds predicates remain signed
  after zero-extension of WORD inputs. Pasboot has no WORD-family types;
  its signed CHAR comparison quirk is immaterial to ASCII keyword/digit use.
- Both `FoldConstInt` implementations truncate toward zero, use dividend-signed
  MOD and reject constant zero divisors; see the
  [constant consumer rules](dialect_notes.md#constant-divmod-and-consumer-invariants). Source DIV/MOD uses
  include decimal extraction, alignment/eightbyte division, positive
  power-of-two tests, wait-status decoding and nonnegative proxy ring indices.
  No floor-rounding or negative-divisor workaround is needed for self-hosting.
  Native negative constant/runtime twins and pasboot's `-7 DIV/MOD 2` fixture
  pin this rule; the Python reference is not the arithmetic oracle.

### Arithmetic source responsibilities

| Compilands under `src/` | Arithmetic responsibility |
| --- | --- |
| `lexer`, `ps_base`, `ps_expr`, `ps_stmt`, `ps_decl`, `parser` | Positions, flags, depths, digits and token-buffer sizes; numeric-label key wrapping only. ASCII arithmetic and bounded Str255 lengths fit. |
| `tc_base`, `tc_types`, `tc_expr`, `tc_stmt`, `tc_decl`, `typechecker` | Symbol/type/field IDs, tables, depths, parameters and wide limits; explicit fold-overflow detection, not modular table exhaustion. |
| `cg_base`, `cg_util`, `cg_types`, `cg_symbols`, `cg_decl`, `codegen` | Scope/table IDs, layout/ABI/allocation/shadow sizes, parameter/register budgets and wide limits; explicit fold-overflow detection. |
| `cg_expr`, `cg_expr_shape`, `cg_expr_support`, `cg_expr_literals`, `cg_expr_sets`, `cg_expr_vector`, `cg_stmt`, `cg_io` | Emit user LLVM arithmetic/guards and count lanes/selectors/labels/arguments. LLVMBuildAdd emits user IR, not host Pascal addition; no host checksum. |
| `jsonutil`, `features`, `argparse` | Buffer/copy sizes, bounded strings and CLI counters; explicit C numeric bridges avoid TRUNC narrowing. |
| `driver`, `astcompare`, `pretty81`, `sysutil` | CLI/status, AST traversal, formatting and filesystem operations; no modular counters. |
| `bytebuf`, `jsonx`, `netsock`, `httpio`, `proxycore`, `proxy` | Finished-compiler buffer sizes, decimal/HTTP formatting/parsing, positions and bounded ring/edit-distance calculations; no hash/checksum dependency. |

### Arithmetic hardening limits

A valid-source fixed point is not proof that arbitrary hostile/oversized input
cannot exhaust compiler counters or allocations. These remain limits, not
reasons for blanket MATHCK-:

- `lexer:ScanNumber`, `ParseSignedIntStr` and `ps_base:StrToRealVal` can exceed
  accumulator/exponent widths on oversized numeric text. INTEGER64 literal
  precision and WORD64 admission limitations remain; checking must not be
  weakened to preserve garbage values.
- Host constant/bound calculations in `tc_expr`, `cg_types` and `tc_decl`
  need exact diagnostics/width handling on pathological expressions. The
  `FoldArith` guards are not a proof that every constant calculation is safe.
  Gen1 C DIV/MOD has no general zero or MIN64/-1 helper: audited bootstrap
  inputs avoid these cases. Pasboot is not safe for arbitrary arithmetic edge
  programs merely because a fixed point succeeds.
- Buffer doubling in `lexer`, `jsonutil`, `ps_base`, `bytebuf`, INTEGER
  line/column counters and aggregate layout/shadow products can outgrow their
  representable widths or allocations. Table guards do not prove all sizes
  safe; impose limits/guards, never modular allocation sizes.
- `cg_util:IntToStr255` and `cg_symbols:InitckIntText` negate INTEGER32
  without widening; its minimum has no positive INTEGER32 magnitude. Ordinary
  bootstrap inputs avoid it. Widen the magnitude as `bytebuf:BufAppendInt`
  does if that domain is needed; do not disable checks. `pretty81:IntToStr`
  instead formats the full signed INTEGER64 domain using negative-domain
  digit extraction (including MIN64), and IntLiteral reads `GetInt64` so
  exact JSON companions survive formatting. `tests/contract/pretty81_integers.sh`
  pins parsed/typed round-trips, idempotence and O0–O3 runtime values. This does
  not repair REAL precision/spelling or admit new WORD64 literal syntax.

## How the C is organized

- `LSTRING(n)`, arrays, and records become C structs. Thus assignment and
  value parameters copy the whole value, and `SIZEOF` is the C `sizeof`.
- Strings and arrays are the same type when they have the same shape.
  `Str255` and `ArgStr` are both `LSTRING(255)`, so they are one type.
- A spliced interface gives `extern` declarations. The implementation's
  repeated `CONST` and `TYPE` blocks are absorbed. Its repeated `VAR` block
  gives the definitions.
- Exported routines and variables have external linkage. All other routines
  and variables are `static`.
- A `[C]` routine gets a private C name. An `asm` label binds that name to
  the real symbol. Thus the Pascal prototypes of libc functions do not
  conflict with the C headers.
- A `PROGRAM` becomes `main`. It calls `pascal_init_<unit>` for each unit
  that it reaches through `USES`, lowest unit first.
- `bootstrap/prelude.h` contains the string comparison, `CONCAT`, and
  `WRITE` helpers. They use only libc. The Pascal runtime library is linked
  only for the `[C]` routines that the sources declare.

## How the subset is tested

`tests/contract/mathck_bootstrap_audit.sh` (in `make test`) pins local label-key
lexer flags/restoration, wide i64 limit arithmetic in actual `tc_expr`/`cg_decl`
O0 IR (including checked intrinsics), numeric-label AST keys in generations
1–4/both dialects (8 cells), and high-bit LABEL/GOTO output under both settings,
both dialects and O0–O3 (16 cells). It runs
`tests/unit/pasboot/mathck_ignored.pas` at Clang O0–O3 (4 cells): ignored
on/off/numeric settings, native INTEGER wrapping, a representable INTEGER64
2^31 build-up and truncating negative DIV/MOD. Malformed bare/numeric/trailing
settings are rejected; standard pasboot tests retain the unsupported DEBUG
probe. See the [test guide](testing/mathck.md#bootstrapself-hosting-arithmetic-audit)
for the suite entry point. This focused audit is not the clean fixed-point gate
and does not exhaustively check every source's opt-outs or hostile input.

- `tests/check/bootstrap_subset.sh` checks that every generation-1 compiland
  stays inside the subset.
- `tests/unit/pasboot.sh` (`make test-quick`) runs one fixture for each
  feature in the semantics list, and checks that the unsupported constructs
  are rejected.
- `make test-bootstrap` builds generations 1 to 4 with `pascal1981`,
  `python`, and `python3` replaced by stubs that fail. Then it compares
  generation 3 with generation 4.
- `scripts/cross-bootstrap-check.sh` builds generation 1 with `pasboot` and
  with the Python reference, and then builds generation 2 from each. It
  requires identical IR for each unit and identical binaries. It needs
  `pascal1981`. Set `USE_PYTHON_REFERENCE=1` to make `scripts/build-stage.sh`
  use the Python reference for generation 1. This option stays for one
  release.
