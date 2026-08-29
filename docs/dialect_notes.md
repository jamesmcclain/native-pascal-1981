# Dialect notes: dialects, widths, and the things that fail silently

This is the document to read before writing Pascal in this repository. It
records the parts of the 1981 IBM Pascal dialect that do not behave the way a
modern Pascal or C programmer expects, with a bias toward the ones that fail
*silently* — no error, no warning, just a wrong number somewhere downstream.

Everything here has been verified against the native compiler in this tree
rather than inferred from its sources.

## There are two dialects

The native language has a **vintage core** and an **extended** surface.
**Vintage** is the faithful 1981 language: `INTEGER`, `WORD`, `REAL`, `CHAR`,
`BOOLEAN`, `STRING`, `LSTRING`, and nothing else. Enum I/O is ordinal, `::N`
precision is ignored on strings, and there are no wide types.

**Extended** adds an umbrella of extensions. The ones that matter here are:

- `wide-integers` — `INTEGER8`/`INTEGER32`/`INTEGER64` and
  `WORD8`/`WORD32`/`WORD64`, the `INTEGER16`/`WORD16` synonyms, **and wide
  integer constants**.
- `wide-reals` — `REAL32`, and `REAL64` as a synonym for `REAL`.
- `symbolic-enum-io`, `string-precision`, `readset-set-literal`,
  `tuning-hints` (launch-bound attributes and `{$UNROLL n}`).

The native driver validates `--dialect <value>` and passes it to the parser,
typechecker, and code generator. The typechecker and code generator use a
shared feature set. Vintage mode rejects wide scalar type names, `WRD8`, C-ABI
type aliases, `[C]`, `[CDECL]`, `[VARARGS]`, anonymous `READSET` set
literals, `{$UNROLL}`, and launch-bound attributes. DEVICE units can use wide
scalar types and tuning hints independently of the command-line dialect.

Other gates are not implemented yet. For example, vintage mode still accepts
wide integer constants, symbolic enum I/O, and string precision. Thus,
`--dialect vintage` is not yet a complete conformance check.

### Command-line contract

The driver and each standalone stage default to the `vintage` dialect. The
`--dialect` option accepts only the case-sensitive values `vintage` and
`extended`. DEVICE is a compiland kind, not a command-line dialect.

The driver reports `error: --dialect requires an argument` when the value is
missing. It reports `error: invalid dialect '<value>'; expected 'vintage' or
'extended'` when the value is invalid. Standalone stages report equivalent
errors for the same conditions.

The driver does not pass a dialect option to the lexer. It invokes the other
stages as follows:

```text
parser --dialect <value>
typechecker --dialect <value>
codegen --dialect <value>
```

These command lines are the implemented transport contract. The typechecker
and code generator resolve the selected dialect to shared feature state. They
use that state for scalar types, C interoperability, anonymous `READSET` set
literals, and tuning hints. Later work will apply it to the remaining language
constructs.

Feature overrides such as repeated `-f wide-integers` options are not part of
the native command-line contract yet. `argparse` stores one value for each
registered option and cannot accumulate repeated values. Its API and storage
must be extended before native stages can implement repeatable `-f` options.

The scope tags below state where a rule applies: **[both]** means a
vintage-core rule that remains true in the native extended surface;
**[extended]** means the rule concerns an extension; and **[native]** means a
limitation of this repository's implementation. A native limitation applies
to every program compiled by the native pipeline unless the text says
otherwise.

## READSET and tuning hints

In vintage mode, the final `READSET` argument must be a declared `SET OF CHAR`
value. Extended mode also accepts an anonymous set constructor, such as
`['a'..'z']`. This rule does not remove vintage support for declared sets.

The `{$UNROLL n}` directive requires extended mode or DEVICE code. The count
must be a positive integer. The lexer always records the directive. The
typechecker decides whether the selected dialect permits it.

`[MAXNTID]`, `[REQNTID]`, and `[MINCTASM]` require extended DEVICE code. DEVICE
context also enables them when the command-line dialect is vintage. These
attributes are valid only on exported kernel procedures. Dimensions must be
positive integer literals. CUDA axis and total-thread limits apply to
`MAXNTID` and `REQNTID`, and those two attributes cannot occur on the same
kernel.

## Integer widths

`INTEGER` and `WORD` are **[both]**. Every wide type in this table is
**[extended]**; a vintage program must not use it.

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

Note that `INTEGER`'s range is symmetric: `-32768` is not a writable literal.

## Integer literals take their width from context **[extended]**

A literal is *not* limited to 16 bits in extended mode. It is typed by the
context it appears in, so all of these are correct there:

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

`tests/golden/19_wide_int_literals.pas` pins this behavior.

A literal too large for its target type must not be relied on:

```pascal
VAR s: INTEGER;
BEGIN
  s := 40000;
END
```

The native compiler does not diagnose this case; it wraps silently, storing
`-25536`. This is a **[native, extended]** limitation: vintage source should
not contain the wide literal, while extended source can accidentally narrow it.

**Historical note, because the wrong version of this was believed for a
while:** until recently the native compiler *did* truncate every literal to 16
bits, and it looked exactly like a property of the dialect. It was not. Three
separate places inside the compiler read a literal's value through `TRUNC` or
stored it in a 16-bit field — the parser's token record, `jsonutil`'s
`AddIntField`, and `Real64ToInt64` in the constant folder — so `40000` became
`-25536` on its way into the AST and nothing downstream could recover it. If
you find yourself writing `n := 65; n := n * 1000;` to avoid a wrap, you are
working around a bug that no longer exists.

## `TRUNC` and `ROUND` return `INTEGER`, so they narrow to 16 bits **[both]**

This one is real in both dialects, and it is what caused the bug above. Both produce a 16-bit
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

## Native limitations **[native]**

Recorded rather than fixed. These are implementation limitations, not
vintage-language restrictions.

- **A literal out of range for its context type [extended].** The native
  compiler wraps it silently. Its type model collapses every integer width
  into one kind (see the comment at the top of `src/tc_decl.pas`), so it has
  no target width to check.
- **Implicit narrowing [extended].** The native compiler accepts an implicit
  wide-to-`INTEGER` assignment. Use `RETYPE(INTEGER, n)` to make the
  truncation explicit.
- **Array index bounds [both].** They are `INTEGER`-ranged in the vintage core
  and the extended surface. A bound outside that range is rejected by the
  native compiler; its message comes from `CheckedIndexBound` in
  `src/cg_types.pas`. Before that check existed, `ARRAY [0..40000] OF CHAR`
  silently emitted `[4294941761 x i8]` — a 4 GB array that failed much later,
  at link time, with a relocation overflow nothing could trace back to the
  bound.

## Other things that cost time **[both, unless marked otherwise]**

None of these are width-related, but all have produced a baffling error at
least once:

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
- **There is no implicit `INTEGER64` to `REAL` conversion [extended]**, and
  `FLOAT()` accepts only a plain `INTEGER`. The runtime's
  `pas_int64_to_double` exists because there is no way to write that
  conversion in Pascal.

## Checklist before committing Pascal in this tree

1. For extended code, every length, offset, capacity, byte count and file size
   is `INTEGER32`. A vintage program has no such type; keep its values within
   `INTEGER` or use an appropriate vintage representation.
2. No `TRUNC` or `ROUND` on a value that can exceed 32767 **[both]**.
3. A literal assigned to a plain `INTEGER` is inside `-32767..32767`; the
   native compiler will not tell you if it is not.
4. Do not treat `bin/pascal1981 --dialect vintage` as a vintage conformance
   check; the native pipeline does not implement dialect selection.
5. `make test-bootstrap` still reaches a byte-identical `gen3`/`gen4`.
