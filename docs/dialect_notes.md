# Dialect notes: widths, literals, and the things that fail silently

This is the document to read before writing Pascal in this repository. It
records the parts of the 1981 IBM Pascal dialect that do not behave the way a
modern Pascal or C programmer expects, with a bias toward the ones that fail
*silently* — no error, no warning, just a wrong number somewhere downstream.

Everything here has been verified against the compilers in this tree rather
than inferred from the sources. Where the native compiler and the reference
disagree, both behaviours are given.

## There are two compilers, and they are not equally strict

- **The reference compiler** is the out-of-repo Python `pascal1981` package
  (see the README's prerequisites). It builds `gen1`, the first native stage.
- **The native compiler** is `bin/pascal1981`, built from this tree.

Anything in the bootstrap set — `src/lexer.pas`, `src/parser.pas`,
`src/typechecker.pas`, `src/codegen.pas`, `src/driver.pas`, `src/jsonutil.pas`
and the `cg_*` units — must be accepted by **both**, because `gen1` is built by
the reference. Everything else (`src/bytebuf.pas`, `src/argparse.pas`,
`src/netsock.pas`, `src/jsonx.pas`, `src/httpio.pas`, `src/proxycore.pas`,
`src/astcompare.pas`, and every fixture under `tests/`) is built by the
finished native compiler and only has to satisfy that one.

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
| `INTEGER` | **16-bit signed** | the default, and the source of most surprises |
| `WORD` | 16-bit unsigned | `0..65535` |
| `INTEGER32` | 32-bit signed | what you almost always want for a length or an offset |
| `INTEGER64` | 64-bit signed | |
| `CINT` | 32-bit signed | C `int`, for `[C]; EXTERN;` declarations |
| `CLONG` | 64-bit signed | C `long` |
| `CSIZE_T` | 64-bit unsigned | C `size_t` |
| `REAL` | 64-bit float | `REAL32` is the 32-bit one |

Arithmetic on `INTEGER32` variables is genuinely 32-bit:

```pascal
n := 30000; n := n + 30000;    { 60000, correct }
```

## Integer literals are 16 bits, wherever they appear

This is the single most expensive thing in this document. **An integer literal
is a 16-bit value**, regardless of what it is assigned to:

```pascal
VAR n: INTEGER32;
BEGIN
  n := 65000;      { n is -536 }
  n := 40000;      { n is -25536 }
  n := 100000;     { n is -31072 }
```

No error, no warning. `CONST BIG = 40000;` wraps the same way. A `WORD` target
is the exception, because the same 16-bit pattern read as unsigned is the
value you wrote: `wv := 60000` really is 60000.

Write large constants by arithmetic instead, and say why in a comment so the
next reader does not "simplify" it back:

```pascal
max_head := 65;
max_head := max_head * 1000;      { 65000 -- written as a literal it wraps }
```

Real bugs this has caused in this tree, all of them silent:

- A `Content-Length` overflow guard written `IF total > 200000000` wrapped to a
  small number, so it fired on *every* valid length and every request parsed as
  malformed (`src/httpio.pas`).
- `malloc(100000)` became `malloc(-31072)`, returned `NIL`, and segfaulted far
  from the cause (`tests/integration/bytebuf_unit.pas`).
- `HttpReadHead(fd, raw, req, 65000, 5000)` passed `-536` as the maximum header
  size, which failed the `max_head > 0` guard inside and switched the ceiling
  off entirely. Three call sites had it, and nothing noticed because no test
  reached the too-large path at all.

## `TRUNC` and `ROUND` return `INTEGER`, so they narrow to 16 bits

Both produce a 16-bit result even when assigned to an `INTEGER32`, and for a
value outside 16-bit range the result is not merely wrapped — LLVM's
float-to-int conversion is poison when it does not fit, so it is genuine
garbage:

```pascal
r := 100000.0;
n := TRUNC(r);     { observed: 1227885960 }
n := ROUND(r);     { observed: -31072 }
```

Do not use `TRUNC` to read a number out of JSON, a file, or anything else that
can exceed 32767. `jsonx`'s `JxIntValue` and `jsonutil`'s `GetInt` go through
`pas_cjson_int32` in the runtime instead, which converts in 32 bits and clamps
out-of-range values.

`ORD` does not have this problem: `ORD` of an `INTEGER32` keeps its width.

## Known divergences from the reference

These are recorded rather than fixed. Each is a real difference in behaviour
between the two compilers, and none currently affects the bootstrap.

- **Out-of-range literals.** The reference rejects any integer literal outside
  `-32767..32767` outright ("Integer literal 40000 out of range for INTEGER").
  The native compiler accepts it and wraps, as above.
- **Array bounds above 32767.** `ResolveIntLiteral` in `src/cg_types.pas`
  returns `INTEGER`, so `ARRAY [0..40000] OF CHAR` wraps its upper bound to
  `-25536` and emits `[4294941761 x i8]` — a 4 GB array that fails at link time
  with a relocation overflow. The reference rejects the literal instead.
- **Implicit narrowing**, described above.

## Other things that cost time

None of these are width-related, but all of them have produced a baffling
error at least once:

- **A single-character quoted literal is a `CHAR`, not a string.** `JxGet(node,
  'x')` fails to typecheck with "Argument type mismatch" against an `LSTRING`
  parameter while `JxGet(node, 'xy')` is fine. The error says nothing about the
  literal.
- **Comments do not nest.** A `{ }` comment containing `{` or `}` — including
  in prose, or in an example — ends early, and the failure is reported as
  "Lexer Error: unrecognized character" somewhere further down.
- **Reserved words with no visible role.** `VALUE`, `LABEL`, `ORIGIN`,
  `OVERLAY` and `FORTRAN` are reserved; using one as a parameter or variable
  name gives a parser error naming the token.
- **`CONCAT`'s destination must be a bare variable**, never a record field.
  Build the string in a local and assign it afterwards.
- **`ADR` takes a bare identifier only** — never `ADR rec.field`.
- **Pointers compare only with `=` and `<>`.** There is no pointer subtraction
  and no relational comparison, so a C-style `while (p < end)` walk does not
  compile. Carry an `INTEGER32` index against a base pointer instead.
- **Two `LSTRING(255)` types from different units are not interchangeable**,
  neither as a `VAR` parameter nor by assignment. Copy character by character.
  See `~/pascal1981-runtime-linking-notes.md` for the plan to remove this.
- **`CONST` accepts foldable integers, reals and `CHAR`s only.** String
  constants are not supported, and a `CONST` value cannot be a function call.

## Checklist before committing Pascal in this tree

1. Every length, offset, capacity, byte count and file size is `INTEGER32`.
2. No integer literal above 32767 anywhere — search for one and check each hit.
3. No `TRUNC` or `ROUND` on a value that can exceed 32767.
4. If the file is in the bootstrap set, it compiles under the reference too:
   `pascal1981 --dialect extended -c src/thefile.pas -o /tmp/x.o`.
5. `make test-bootstrap` still reaches a byte-identical `gen3`/`gen4`.
