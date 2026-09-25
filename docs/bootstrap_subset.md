# The bootstrap subset

Generation 1 of the compiler is built by `bootstrap/pasboot`, a small C99
program in this tree. `pasboot` translates one Pascal compiland to one C
translation unit, and `clang` compiles it. No other Pascal compiler, and no
Python, takes part in `make bootstrap`.

`pasboot` accepts only a narrow part of the extended dialect: the part that
the generation-1 sources use. This document defines that part. It is a
contract. A change to a generation-1 source must stay inside it, or the
bootstrap fails.

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

Run `make check-bootstrap-subset` to check these files. It runs
`pasboot --parse-only` on each compiland. `make test` runs it too.

## What the subset contains

| Area | Contents |
| --- | --- |
| Compilands | `PROGRAM p(input, output)`; `IMPLEMENTATION OF u` after its spliced `INTERFACE; UNIT u [(exports)]; ... END;`; `USES`; `(*$INCLUDE:'x.inc'*)` or `{$INCLUDE:'x.inc'}`, the only metacommand |
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
- every metacommand except `$INCLUDE`

To widen the subset, change `bootstrap/parse.c` or `bootstrap/emit.c`, add a
fixture in `bootstrap/tests/`, and update this document.

## Semantics

`pasboot` gives the subset the meaning that the native compiler gives it.
These rules are the ones that a C programmer does not expect:

- `INTEGER` is 16 bits. An operation on two integer operands is done at the
  width of the wider operand, and the result wraps at that width. The C is
  compiled with `-fwrapv`.
- All integer comparisons are signed. `CHAR` comparisons are signed too.
- `AND` and `OR` evaluate both operands. Only `AND THEN` stops early.
- `/` always gives a `REAL`. An integer operand converts to `REAL` when the
  other operand is a `REAL`.
- `ORD` gives a 32-bit result. `CHR` keeps the low 8 bits.
- `RETYPE` between integer types keeps the low bytes when it narrows, and
  sign-extends when it widens.
- `TRUNC` gives a 16-bit `INTEGER`.
- A `FOR` loop evaluates its limit one time. After the loop, the control
  variable is one step past the limit. A limit at the maximum of its type
  stops the loop. (The native compiler wraps around and does not stop.)
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

- `make check-bootstrap-subset` checks that every generation-1 compiland
  stays inside the subset.
- `bootstrap/tests/run.sh` (`make test-pasboot`) runs one fixture for each
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
