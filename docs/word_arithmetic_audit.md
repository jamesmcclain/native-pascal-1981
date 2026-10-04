# Scalar WORD arithmetic correctness audit

On `port-mathck`, scalar WORD-family DIV/MOD and ordering now use unsigned
LLVM instructions at 8, 16, 32 and 64 bits. This fixes G14–G17 and G21,
independently of MATHCK. Python compiler parity is not an acceptance criterion.

## Lowering and scope

`CodegenBinOp` in `src/cg_expr.pas` selects `udiv`/`urem` and unsigned ordering
predicates using the operand type **after** existing literal adaptation and
width promotion. EQ/NE remain signedness-neutral. INTEGER-family division,
remainder and ordering remain signed. Wrapping add/sub/mul are unchanged.

This change does not decide mixed INTEGER-variable/WORD type admission or
promotion; that remains a separate prerequisite. It does not add MATHCK
instrumentation, zero-divisor guards, signed MIN/-1 handling, constant-folder
changes, or FOR endpoint fixes. In particular, unsigned division by zero is
still LLVM undefined behavior; all executed division tests here use nonzero
divisors. No frozen reference AST is changed.

## Comparison-site audit

Reviewed `LLVMBuildICmp` sites in `src/cg*.pas`:

- Scalar expression ordering: fixed by selecting WORD-family unsigned
  predicates at the adapted width. INTEGER signed controls are retained.
- CASE (`cg_stmt.pas`): dispatch compares labels with `icmp eq`, after coercion
  to the selector type. There is no signed ordering to replace. High-bit and
  maximum labels are tested at all four widths. CASE label ranges remain
  unsupported; this change does not implement them.
- Set membership (`cg_expr_sets.pas`): supported ordinals are normalized to
  i16 by the caller, then sign-extended to i64. An **unsigned** `< 256` bounds
  test excludes negative/high-bit patterns; the selected safe ordinal is used
  for the bit lookup. No predicate change is needed. INTEGER high-bit-pattern
  rejection and in-range membership are tested. WORD in an INTEGER-based set
  is a type error; even a matching declared WORD set currently reaches a
  codegen rejection. Both are explicit rejection probes, not claims of WORD
  membership support. The latter is an adjacent admission gap to revisit
  separately, not a reason to substitute signed bounds comparisons.
- Set constructors: an unsigned i16 `> 255` test guards elements. Range-loop
  signed comparisons operate on admitted INTEGER/CHAR/BOOLEAN/enum bounds,
  not WORD. Set equality/subset checks compare bitvectors for equality.
- Fixed/SUPER array index checks (`cg_expr.pas`), subrange checks
  (`cg_types.pas`), and vector descriptor bounds (`cg_expr_vector.pas`):
  unsigned sources are zero-extended into a wider signed domain (i128).
  Signed comparisons in that domain are correct, including WORD64; changing
  them blindly to unsigned would break negative lower bounds. Existing
  index/subrange regression suites and focused zero-extension IR assertions
  cover these contracts.
- VECTOR lane arithmetic/comparisons already choose unsigned WORD DIV/MOD and
  ordering. Their zero-divisor/MATHCK boundary work remains separate.
- FOR (`cg_stmt.pas`): ordinary WORD controls still use signed loop comparisons
  and integer endpoint stepping remains unsafe. G18/G19 and the next planning
  item stay open; scalar expression fixes must not be mistaken for loop fixes.
- Other comparisons are string lengths/strcmp results, signed implementation
  counters/status values, pointer/NIL or initialization-state equality tests.
  ABS's signed-negative test is builtin arithmetic, not surface WORD ordering.
  It currently mishandles high-bit WORD arguments; unsigned ABS must be an
  identity. This correction remains in the separate builtin implementation
  slice, alongside INTEGER ABS overflow enforcement.

## Self-hosting and validation

Validation passed from a clean build:

```sh
make clean
make -j16 bootstrap check-bootstrap-subset
make -j16 test-native
./tests/mathck_word_scalar.sh
./tests/mathck_baseline.sh
git diff --check
```

All 29 gen1 compilands passed the bootstrap subset check; lexer, parser,
typechecker and codegen reached a byte-identical gen3/gen4 fixed point. The
full native suite passed, including 331 main fixtures, 42 checklit fixtures,
21 frozen-AST comparisons and all focused contract scripts. The MATHCK
baseline passed all 45 probes / 168 cells. No compiler-source workaround or
intentional signed-WORD dependency was found requiring a change in this slice.
The broader intentional-wraparound/MATHCK-enabled bootstrap audit remains open.

`tests/mathck_word_scalar.sh` is wired into `make test-native`. It checks native
expected outputs at O0/O1/O2/O3 with MATHCK both on and off, in both dialects
for WORD and extended mode for WORD8/32/64 (24 runtime cells). It covers high
bits, maximum values, low-value controls, both operand orders, equality,
literal adaptation, unsigned width promotion, signed INTEGER controls, CASE,
set admission and wider index-check IR. O0 assertions require unsigned
DIV/MOD and all four unsigned ordering predicates at every width, as well as
unchanged signed controls. `mathck_baseline.json` flips G14–G17 and G21 from
known-gap output to correct output. These tests do not claim MATHCK protection.

## WORD to REAL conversion (found by the MATHCK builtin audit)

Every integer-to-floating conversion used `sitofp`, so WORD-family values
converted as signed: `FLOAT(w)` with `w = 65535` was `-1.0`, `1.0 + w` was
`0.0`, and `FLOAT` of WORD32 `4000000000` was `-294967296.0`. `IntToFloat`
(`src/cg_types.pas`) now chooses `uitofp` for the WORD family at every site:
FLOAT and the libm argument conversion (`RealArgToDouble`), mixed
REAL/integer operands and `/` promotion in `CodegenBinOp`, and
`CoerceForAssign`. `tests/fixtures/mathck/word_scalar{,_wide}.pas` pin
`FLOAT`, mixed REAL `+`/`*` and wide maxima (WORD64 MAX is
`18446744073709551616.0` as a double), and `tests/mathck_word_scalar.sh`
requires `uitofp` at 8/16/32/64 bits in the O0 IR.
