# Dialect notes: dialects, widths, and the things that fail silently

This is the document to read before writing Pascal in this repository. It
records the parts of the 1981 IBM Pascal dialect that do not behave the way a
modern Pascal or C programmer expects, with a bias toward the ones that fail
*silently* — no error, no warning, just a wrong number somewhere downstream.

Everything here has been verified against the compilers in this tree rather
than inferred from the sources. Where the native compiler and the reference
disagree, both behaviours are given.

## There are two dialects

The compiler takes `--dialect vintage` or `--dialect extended`.

**Vintage** is the faithful 1981 language: `INTEGER`, `WORD`, `REAL`, `CHAR`,
`BOOLEAN`, `STRING`, `LSTRING`, and nothing else. Enum I/O is ordinal, `::N`
precision is ignored on strings, and there are no wide types at all.

**Extended** turns on an umbrella of extensions, the ones that matter here
being:

- `wide-integers` — `INTEGER8`/`INTEGER32`/`INTEGER64` and
  `WORD8`/`WORD32`/`WORD64`, the `INTEGER16`/`WORD16` synonyms, **and wide
  integer constants**.
- `wide-reals` — `REAL32`, and `REAL64` as a synonym for `REAL`.
- `symbolic-enum-io`, `string-precision`, `readset-set-literal`,
  `tuning-hints` (launch-bound attributes and `{$UNROLL n}`).

Everything in this repository is compiled `--dialect extended`, including the
compiler's own sources, so that is the dialect these notes describe unless a
section says otherwise. If you are writing vintage-dialect code, `INTEGER32`
does not exist and neither does any literal that does not fit `INTEGER`.

Two orthogonal policy flags exist that `--dialect` does not touch:
`strict-word-int` and `noalias-kernel-params`. Both are off by default and
must be asked for by name.

## There are two compilers, and they are not equally strict

- **The reference compiler** is the out-of-repo Python `pascal1981` package
  (see the README's prerequisites). It builds `gen1`, the first native stage.
- **The native compiler** is `bin/pascal1981`, built from this tree.

Anything in the bootstrap set — `src/lexer.pas`, `src/parser.pas`,
`src/typechecker.pas`, `src/codegen.pas`, `src/jsonutil.pas` and the `ps_*`,
`tc_*` and `cg_*` units — must be accepted by **both**, because `gen1` is built
by the reference. Everything else (`src/bytebuf.pas`, `src/argparse.pas`,
`src/netsock.pas`, `src/jsonx.pas`, `src/httpio.pas`, `src/proxycore.pas`,
`src/driver.pas`, `src/astcompare.pas`, and every fixture under `tests/`) is
built by the finished native compiler and only has to satisfy that one.

This matters because the reference is stricter in places. It rejects an
implicit narrowing that the native compiler accepts:

```pascal
VAR n: INTEGER32; s: INTEGER;
BEGIN
  s := n;        { native: compiles. reference: "Cannot assign INTEGER32 to INTEGER" }
```

Use `RETYPE(INTEGER, n)` to make the truncation explicit. In the bootstrap set
you have no choice; elsewhere it is still the better thing to write, because
the truncation is real either way and `RETYPE` says so.

## Integer widths

| Type | Width | Notes |
|---|---|---|
| `INTEGER` | **16-bit signed** | the default; range is `-32767..32767` |
| `WORD` | 16-bit unsigned | `0..65535` |
| `INTEGER32` | 32-bit signed | extended only; what you want for a length or an offset |
| `INTEGER64` | 64-bit signed | extended only |
| `WORD8`/`WORD32`/`WORD64` | unsigned | extended only |
| `CINT` | 32-bit signed | C `int`, for `[C]; EXTERN;` declarations |
| `CLONG` | 64-bit signed | C `long` |
| `CSIZE_T` | 64-bit unsigned | C `size_t` |
| `REAL` | 64-bit float | `REAL32` is the 32-bit one, extended only |

Note that `INTEGER`'s range is symmetric: `-32768` is not a writable literal,
and the reference rejects it.

## Integer literals take their width from context

A literal is *not* limited to 16 bits. It is typed by the context it appears
in, so all of these are correct in the extended dialect:

```pascal
VAR n: INTEGER32; w: INTEGER64;
CONST BIG = 100000;
BEGIN
  n := 40000;          { 40000 }
  n := 16#9C40;        { 40000, radix notation }
  n := -70000;         { -70000 }
  n := BIG;            { 100000 }
  w := 5000000000;     { 5000000000 }
```

`tests/golden/19_wide_int_literals.pas` pins this, and its output matches the
reference compiler exactly.

What *is* an error is a literal too large for the type it lands in:

```pascal
VAR s: INTEGER;
BEGIN
  s := 40000;   { reference: "Integer literal 40000 out of range for INTEGER" }
```

The native compiler does not yet produce that diagnostic — it wraps silently,
storing `-25536`. That is the one live divergence on literals, and it is
listed below.

**Historical note, because the wrong version of this was believed for a
while:** until recently the native compiler *did* truncate every literal to 16
bits, and it looked exactly like a property of the dialect. It was not. Three
separate places inside the compiler read a literal's value through `TRUNC` or
stored it in a 16-bit field — the parser's token record, `jsonutil`'s
`AddIntField`, and `Real64ToInt64` in the constant folder — so `40000` became
`-25536` on its way into the AST and nothing downstream could recover it. If
you find yourself writing `n := 65; n := n * 1000;` to avoid a wrap, you are
working around a bug that no longer exists.

## `TRUNC` and `ROUND` return `INTEGER`, so they narrow to 16 bits

This one is real, and it is what caused the bug above. Both produce a 16-bit
result even when assigned to an `INTEGER32`, and for a value outside 16-bit
range the result is not merely wrapped — LLVM's float-to-int conversion is
poison when it does not fit, so it is genuine garbage:

```pascal
r := 100000.0;
n := TRUNC(r);     { observed: 1227885960 }
n := ROUND(r);     { observed: -31072 }
```

Do not use `TRUNC` to read a number out of JSON, a file, or anything else that
can exceed 32767. The runtime provides `pas_cjson_int32`, `pas_cjson_int64`
and `pas_double_to_int64` for exactly this, and `jsonx`'s `JxIntValue`,
`jsonutil`'s `GetInt` and the compiler's own constant folder all go through
them now.

`ORD` does not have this problem: `ORD` of an `INTEGER32` keeps its width.

## Known divergences from the reference

Recorded rather than fixed. None currently affects the bootstrap.

- **A literal out of range for its context type.** The reference rejects it;
  the native compiler wraps silently. The native typechecker's type model
  collapses every integer width into one kind (see the comment at the top of
  `src/tc_decl.pas`), so it has no context width to check against.
- **Implicit narrowing**, described above.
- **Array index bounds** are `INTEGER`-ranged in this dialect. A bound outside
  that range is rejected by both compilers now, but with different wording;
  the native message comes from `CheckedIndexBound` in `src/cg_types.pas`.
  Before that check existed, `ARRAY [0..40000] OF CHAR` silently emitted
  `[4294941761 x i8]` — a 4 GB array that failed much later, at link time,
  with a relocation overflow nothing could trace back to the bound.

## Other things that cost time

None of these are width-related, but all of them have produced a baffling
error at least once:

- **A single-character quoted literal is a `CHAR`, not a string.** `JxGet(node,
  'x')` fails to typecheck with "Argument type mismatch" against an `LSTRING`
  parameter while `JxGet(node, 'xy')` is fine. The error says nothing about the
  literal.
- **Comments do not nest.** A `{ }` comment containing a brace — including in
  prose, or in an example — ends early, and the failure is reported as "Lexer
  Error: unrecognized character" somewhere further down.
- **Reserved words with no visible role.** `VALUE`, `LABEL`, `ORIGIN`,
  `OVERLAY` and `FORTRAN` are reserved; using one as a parameter or variable
  name gives a parser error naming the token.
- **`CONCAT`'s destination must be a bare variable**, never a record field and
  never a `VAR` parameter. Build the string in a local and assign it after.
- **`ADR` takes a bare identifier only** — never `ADR rec.field`.
- **Pointers compare only with `=` and `<>`.** There is no pointer subtraction
  and no relational comparison, so a C-style `while (p < end)` walk does not
  compile. Carry an `INTEGER32` index against a base pointer instead.
- **Two `LSTRING(255)` types from different units are not interchangeable**,
  neither as a `VAR` parameter nor by assignment. Copy character by character.
- **`CONST` accepts foldable integers, reals and `CHAR`s only.** String
  constants are not supported, and a `CONST` value cannot be a function call.
- **There is no implicit `INTEGER64` to `REAL` conversion**, and `FLOAT()`
  accepts only a plain `INTEGER`. The runtime's `pas_int64_to_double` exists
  because there is no way to write that conversion in Pascal.

## Checklist before committing Pascal in this tree

1. Every length, offset, capacity, byte count and file size is `INTEGER32`.
2. No `TRUNC` or `ROUND` on a value that can exceed 32767.
3. A literal assigned to a plain `INTEGER` is inside `-32767..32767`; the
   native compiler will not tell you if it is not.
4. If the file is in the bootstrap set, it compiles under the reference too:
   `pascal1981 --dialect extended -c src/thefile.pas -o /tmp/x.o`.
5. `make test-bootstrap` still reaches a byte-identical `gen3`/`gen4`.
