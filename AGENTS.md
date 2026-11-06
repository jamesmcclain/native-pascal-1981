# Agent guide

Read this before you change the compiler, the runtime, the tests or any
Pascal source in this repository. [README.md](README.md) explains how to
build and test.

## Compatibility rule: fun, not pathology

The reference is the IBM Pascal Compiler manual (August 1981). Follow it
where it preserves the language's character. Do not follow it where a
historical machine constraint makes modern behavior needlessly
pathological.

- Every deliberate difference from the IBM manual must be documented in
  [`docs/dialect_notes.md`](docs/dialect_notes.md) and pinned by a test.
- Examples of deliberate differences:
  - Native `INTEGER` accepts the full signed 16-bit range, including
    `-32768`, in both dialects.
  - INITCK keeps its state in separate shadow storage. It never reserves a
    program-data value as an "uninitialized" sentinel.
- When the IBM manual is ambiguous, or a choice changes the behavior of
  valid programs, ask the operator before you implement it. Record the
  decision in the dialect notes.

## Know what the checks cover

The checking switches (`$INITCK`, `$MATHCK`, `$RANGECK`, `$INDEXCK`,
`$NILCK`) each cover a stated slice of the language. They are not
whole-program protection.

- For example, INITCK host enforcement covers supported scalar locals,
  formals and results, fixed aggregates, typed pointers, and tracked
  `NEW`/`SUPER ARRAY` storage. External, raw, file and DEVICE storage are
  explicit boundaries. Globals, untracked types and aggregate results are
  outside the checked slice. See the
  [INITCK contract and limits](docs/dialect_notes.md#initialization-checking-host-storage-native).
- Do not describe a check as complete beyond the slice that its contract
  and tests state.

## Writing Pascal in this repository

Read [`docs/dialect_notes.md`](docs/dialect_notes.md) first. The notes tell
you:

- what the vintage and extended dialects each provide;
- the width of each integer type;
- the constructs that fail without an error. For example, `TRUNC` narrows
  its result to 16 bits.

Use the notes' "Checklist before committing Pascal in this tree".

## GPU kernels need `{$MATHCK-}` for integer arithmetic

Integer overflow checking (`$MATHCK`) is on by default. NVPTX code cannot
report a run-time error. Thus, in DEVICE code compiled for NVPTX, each
integer operation that MATHCK would check is a compile-time error:

    MATHCK unsupported boundary: DEVICE arithmetic at line L column C

The operations are `+ - * DIV MOD`, unary `-`, `SUCC`, `PRED`, `ABS` and
`SQR`. Write `{$MATHCK-}` in the kernel to allow them. That arithmetic is
then unchecked and wraps. CPU (serial) DEVICE code is checked like host
code. See
[GPU kernels and `$MATHCK`](docs/dialect_notes.md#gpu-nvptx-kernels-need-mathck--for-integer-arithmetic-extended).
