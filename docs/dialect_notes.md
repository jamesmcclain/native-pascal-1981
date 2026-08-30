# Dialect notes: dialects, widths, and the things that fail silently

This is the document to read before writing Pascal in this repository. It
records the parts of the 1981 IBM Pascal dialect that do not behave the way a
modern Pascal or C programmer expects, with a bias toward the ones that fail
*silently* — no error, no warning, just a wrong number somewhere downstream.

Everything here has been verified against the native compiler in this tree
rather than inferred from its sources.

## There are two command-line dialects

The native compiler has a **vintage** dialect and an **extended** dialect.
The default is `vintage`. This dialect implements the 1981 language, including
16-bit `INTEGER` and `WORD` types. Enum I/O uses ordinals, and string precision
has no effect.

The `extended` dialect activates these feature groups:

- `wide-integers`: `INTEGER8`, `INTEGER32`, `INTEGER64`, `WORD8`, `WORD32`,
  `WORD64`, the `INTEGER16` and `WORD16` synonyms, and wide integer constants.
- `wide-reals`: `REAL32`, and `REAL64` as a synonym for `REAL`.
- `symbolic-enum-io`, `string-precision`, `readset-set-literal`, and
  `tuning-hints`.
- C interoperability types and attributes.

Vintage mode rejects wide scalar type names, `WRD8`, C ABI type aliases, and
`[C]`, `[CDECL]`, and `[VARARGS]`. It also rejects anonymous `READSET` set
literals and `{$UNROLL}` outside DEVICE code.

### Command-line contract

The driver accepts only `vintage` and `extended` as case-sensitive dialect
values. The driver uses `vintage` when the command does not contain a dialect
option. For example:

```sh
bin/pascal1981 -S tests/golden/01_hello.pas -o /tmp/hello.ll
bin/pascal1981 --dialect extended -S tests/golden/01_hello.pas -o /tmp/hello.ll
```

The standalone parser, typechecker, and code generator also default to
`vintage`. These stages accept data only on standard input. An explicit
extended pipeline has this form:

```sh
bin/lexer < tests/golden/01_hello.pas |
  bin/parser --dialect extended |
  bin/typechecker --dialect extended |
  bin/codegen --dialect extended > /tmp/hello.ll
```

The lexer is dialect-neutral. It creates the same token stream for both
dialects and records directive metadata for later stages. Do not pass a
dialect option to the lexer.

The driver reports `error: --dialect requires an argument` when the value is
missing. It reports `error: invalid dialect '<value>'; expected 'vintage' or
'extended'` when the value is invalid. The standalone stages report equivalent
errors.

The typechecker and code generator resolve the dialect to a shared feature
set. They use this set for scalar types, integer ranges, C interoperability,
`READSET`, tuning hints, enum I/O, and string precision.

`DEVICE` is a compiland kind, not a command-line dialect. DEVICE context can
activate wide scalar types and tuning hints independently of `--dialect`.
The command line does not accept `device` as a dialect value.

The native command line does not support `-f` feature overrides. Thus, users
cannot activate one extended feature in vintage mode. Use `--dialect extended`
to activate the complete extended feature set.

### Bootstrap dialect

Compiler sources use extended types and C interoperability declarations.
`scripts/build-stage.sh` passes `--dialect extended` to each parser,
typechecker, and code generator that builds these sources. It does not pass a
dialect option to a lexer. Use `make test-bootstrap` to rebuild all bootstrap
generations and check the `gen3` and `gen4` fixed point.

The scope tags below state where a rule applies: **[both]** means a
vintage-core rule that remains true in the native extended surface;
**[extended]** means the rule concerns an extension; and **[native]** means a
limitation of this repository's implementation. A native limitation applies
to every program compiled by the native pipeline unless the text says
otherwise.

## Enumerated and BOOLEAN I/O

Vintage `WRITE` and `WRITELN` print a user-defined enumerated value as its
numeric ordinal. Vintage `READ` and `READLN` accept a numeric ordinal for that
value. Extended mode writes the member identifier and reads member identifiers
without regard to letter case. These rules apply to standard input and output
and to explicit text files.

`BOOLEAN` keeps its documented vintage behavior in both dialects. Output is
`TRUE` or `FALSE`. Input accepts those names without regard to letter case and
also accepts the numeric ordinals `1` and `0`.

## String precision

In vintage mode, `::precision` does not limit string output. A string literal,
`STRING` value, or `LSTRING` value writes its full contents. In
`value:width:precision`, the width still pads the full value. The compiler
ignores the precision.

Extended mode uses string precision as the maximum number of characters to
write. The width continues to specify the minimum field width. This rule does
not change numeric formatting. Numeric width and precision have the same
behavior in both dialects.

## READSET and tuning hints

In vintage mode, the final `READSET` argument must be a declared `SET OF CHAR`
value. Extended mode also accepts an anonymous set constructor, such as
`['a'..'z']`. This rule does not remove vintage support for declared sets.

The `{$UNROLL n}` directive requires extended mode or DEVICE code. The count
must be a positive integer. The lexer always records the directive. The
typechecker decides whether the selected dialect permits it.

`[MAXNTID]`, `[REQNTID]`, and `[MINCTASM]` require DEVICE code. DEVICE context
also activates them when the command-line dialect is vintage. These attributes
are valid only on exported kernel procedures. Dimensions must be positive
integer literals. CUDA axis and total-thread limits apply to `MAXNTID` and
`REQNTID`. A kernel cannot have both attributes.

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

## Integer constants and context

Vintage decimal and radix constants from `-32767` through `32767` have type
`INTEGER`. Positive constants from `32768` through `65535` have type `WORD`.
Vintage mode rejects constants outside `-32767..65535`. Unary minus does not
make `-32768` valid because its operand is already a `WORD` constant.

An `INTEGER` constant can adapt to a `WORD` context. This includes negative
constants. The conversion keeps the 16-bit pattern, so `-1` becomes `65535`.
An `INTEGER` variable does not adapt in this way.

In extended mode, a literal can use a wide target type. These examples are
valid:

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

A literal too large for its target type is an error:

```pascal
VAR s: INTEGER;
BEGIN
  s := 40000;
END
```

The compiler also rejects implicit narrowing, such as assigning an
`INTEGER32` variable to `INTEGER`. Use an explicit conversion when truncation
is intentional. Assignment, value-parameter, array-index, and `FOR`-bound
contexts apply the same constant range checks.

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

## Differences from the Python compiler

The native compiler and the Python compiler differ for two vintage `WORD`
constant cases. The Python compiler rejects untyped positive constants from
`32768` through `65535`. The native compiler accepts these constants as
`WORD`, as specified in the August 1981 manual.

The Python compiler also rejects negative `INTEGER` constants in a `WORD`
context. The native compiler keeps the 16-bit pattern. For example, it converts
`-1` to `65535` in that context.

The Python command line supports individual `-f` feature overrides. The native
command line supports only the `vintage` and `extended` feature sets.

## Native limitations **[native]**

These are implementation limitations, not vintage-language restrictions.

- **Very large unsigned literals [extended].** The JSON AST stores numbers as
  `REAL`, so decimal `WORD64` literals above `2^53` cannot preserve every bit.
  Use `MAXWORD64` for the upper boundary.
- **Array allocation size [both].** Vintage `WORD` bounds through `65535` are
  retained. A large valid range can still request a correspondingly large
  object from LLVM and the linker.

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
- **`CONST` accepts literals, named constants, and `WRD`/`BYWORD` constant
  constructors.** Multi-character string constants are supported. `WRD(x)`
  and `BYWORD(hi, lo)` are the only function-shaped forms in the vintage
  `constant` grammar; ordinary calls, including `ORD`, `CHR`, `SUCC`, and
  `PRED`, are not valid `CONST` values.
- **There is no implicit `INTEGER64` to `REAL` conversion [extended]**, and
  `FLOAT()` accepts only a plain `INTEGER`. The runtime's
  `pas_int64_to_double` exists because there is no way to write that
  conversion in Pascal.

## Checklist before committing Pascal in this tree

1. For extended code, every length, offset, capacity, byte count and file size
   is `INTEGER32`. A vintage program has no such type; keep its values within
   `INTEGER` or use an appropriate vintage representation.
2. No `TRUNC` or `ROUND` on a value that can exceed 32767 **[both]**.
3. A literal assigned to a plain `INTEGER` is inside `-32767..32767`.
4. Extended code uses an explicit `--dialect extended` option.
5. `make test-bootstrap` reaches a byte-identical `gen3` and `gen4`.
