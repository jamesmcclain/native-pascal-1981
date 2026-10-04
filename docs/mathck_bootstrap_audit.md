# MATHCK bootstrap and self-hosting arithmetic audit

## Scope and conclusion

Audited all 39 `src/*.pas` compilands and their shared `.inc` declarations on
`port-mathck`: arithmetic assignments/returns, DIV/MOD consumers, negation,
bit-pattern conversions, counters, capacity/layout calculations, WORD-sensitive
ordering and numeric limit construction. The 29 generation-1 compilands are
listed in [bootstrap_subset.md](bootstrap_subset.md); the other ten are built
by the finished compiler. There are **no Pascal sources under `runtime/`**;
the runtime implementation is C and is not compiled by generations 2–4.
This audit does not turn C arithmetic into MATHCK operations.

No compiler hash or checksum depends on overflow. The one retained arithmetic
wrap is the parser's numeric-label bit-pattern key. Its multiply/add and sign
conversion now explicitly use MATHCK-; each expression restores the source's
default MATHCK+ immediately. No unit-wide or program-wide opt-out was added.
Normal counters, allocation sizes and numeric values are not modular hashes
and must not be excused with MATHCK- when they exceed their capacity.

This is a source-dependency audit, **not implemented overflow protection** or
a proof that arbitrary hostile/oversized input cannot overflow any compiler
counter. Operator snapshots and checked scalar lowering are still open. The
clean bootstrap proves today's fixed point, not a future checked fixed point;
repeat the bootstrap/full native suite when those gates ship.

## Findings and changes

### Intentional wrap: numeric labels

`ps_base.pas:StrToIntVal` returns an INTEGER used as the key for numeric LABEL,
GOTO and labeled statements (`ps_decl.pas`, `ps_stmt.pas`). The existing parser
uses the low 16-bit pattern, not a signed numeric magnitude: source labels
32767, 32768, 40000 and 65535 become keys 32767, -32768, -25536 and -1.
Declaration, definition and reference all use the same conversion. Preserve
this existing representation, including valid INTEGER -32768, rather than
letting future enabled compiler arithmetic trap on high-bit label keys.

Only `val * 10 + digit` and `-val` are unchecked. The digit subtraction is
within 0..9; it shares the accumulator expression's setting. The loop's `i+1`
and all following routines stay enabled. The function is used only for label
keys, not general user integer literals. This does not approve numeric-label
aliases outside the native 16-bit domain or change label grammar/range policy.

### Limits are wide mathematical values, not wraps

- `tc_expr.pas:MaxWord16Value` now starts with an INTEGER64 variable containing
  32767, then computes `n * 2 + 1`. This avoids relying on a destination's
  later constant adaptation to repair narrow intermediate arithmetic.
- `cg_decl.pas:ConstIntegerType` similarly constructs `max_word16` in INTEGER64
  before comparison. Its former `32767 * 2 + 1` operand was eventually
  rebuilt from a fold by literal adaptation; that must not become a reason
  to ignore an earlier narrow overflow once operator checking is introduced.
- `tc_expr.pas:MaxInteger32Value` and `cg_decl.pas:MaxConstInteger32` already
  use INTEGER64 throughout. `32767^2 * 2 + 4 * 32767 + 1 = 2147483647`;
  every intermediate fits. The associated `*2+1` WORD32 limit is 4294967295,
  also a representable INTEGER64. Keep MATHCK+.
- `cg_types.pas:SuperElementSize` builds its CLONG limit as
  `(2^31-1)*2^32 + (2^32-1) = 2^63-1`. Both multiply and addition fit signed
  64 bits; the divisibility/size guards are not relying on modular results.
- `tc_base.pas`'s predefined max values are literals, not overflowing build-ups.
  Explicit RETYPE narrowing, CHR byte truncation and LLVM bit constants are
  representation conversions, not implicit arithmetic-wrap exemptions.

### WORD ordering and division

There are no compiler Pascal variables/formals declared as WORD/WORD8/WORD32/
WORD64. WORD mentions are user-type tags, names, limits and LLVM lowering.
Array/set bounds are signed INTEGER32 or wider host values, so high-bit native
WORD bounds such as 65535 are positive host values, not negative INTEGER keys.
The label converter above is a separate equality-key representation.

The existing [WORD audit](word_arithmetic_audit.md) covers generated scalar,
CASE, set and widened descriptor comparisons. Scalar ordering/division and FOR
unsigned ordering are now fixed; widened i128 signed bounds predicates must
remain signed after zero-extension of WORD inputs. The compiler does not need
an old signed-WORD workaround. Pasboot does not admit WORD-family types in its
subset; its signed comparison implementation therefore adds no WORD variable
dependency to gen1. Its CHAR signed-ordering quirk is not used for high-bit
ordering by the compiler's ASCII keyword/digit comparisons.

### No floor-folding dependency

Both `FoldConstInt` implementations now truncate, with dividend-signed MOD,
and reject constant zero divisors. Their consumer audit is recorded in
[constant_folding_audit.md](constant_folding_audit.md). Other source DIV/MOD
uses are decimal digit extraction, alignment/eightbyte division, positive
power-of-two validation, wait-status decoding, and nonnegative proxy ring
indices. Negative runtime division in compiler sources does not require floor
rounding. Native negative constant/runtime twin tests and pasboot's -7 DIV/MOD
2 test pin truncation. No floor adjustment or negative-divisor workaround is
needed for self-hosting.

## Compiland inventory and non-wrap classifications

| Files (all under `src/`) | Arithmetic role / disposition |
| --- | --- |
| `lexer`, `ps_base`, `ps_expr`, `ps_stmt`, `ps_decl`, `parser` | Source/token positions, flags, recursion depth, digit accumulation and token-buffer scaling. Only numeric-label accumulation/sign conversion is intentionally modular. ASCII case/digit arithmetic fits INTEGER; bounded Str255 lengths fit 0..255. |
| `tc_base`, `tc_types`, `tc_expr`, `tc_stmt`, `tc_decl`, `typechecker` | Symbol/type/field IDs, table/depth/parameter counts, integer limits and host constant evaluation. Limits stay wide and checked; table exhaustion/host fold overflow is not an intentional wrap. |
| `cg_base`, `cg_util`, `cg_types`, `cg_symbols`, `cg_decl`, `codegen` | Table/scope IDs, layout/ABI sizes, parameter arrays, initialization shadows and integer limits. Small fixed tables/register budgets and guarded depth counters do not need modular arithmetic. Large layout/allocation calculations stay enabled. |
| `cg_expr`, `cg_expr_shape`, `cg_expr_support`, `cg_expr_literals`, `cg_expr_sets`, `cg_expr_vector`, `cg_stmt`, `cg_io` | Emit user arithmetic/LLVM guards and count lanes, selectors, labels and ABI/I/O arguments. An `LLVMBuildAdd` call emits user IR; it is not host Pascal addition. No host checksum/wrap dependency; FOR endpoint and scalar DIV/MOD prerequisites already corrected. |
| `jsonutil`, `features`, `argparse` | Buffer/copy sizes, bounded strings, CLI counters/options; explicit numeric C bridges avoid TRUNC narrowing. No intentional arithmetic wrap. |
| `driver`, `astcompare`, `pretty81`, `sysutil` | CLI/status decoding, AST traversal/string formatting and filesystem interfaces; no modular counters. |
| `bytebuf`, `jsonx`, `netsock`, `httpio`, `proxycore`, `proxy` | Finished-compiler support/tooling: buffer sizes, decimal formatting, HTTP length/status parsing, byte positions and bounded ring/edit-distance calculations. No hash/checksum or overflow-dependent arithmetic. |

## Risks kept visible (not opt-outs)

These are outside the valid-source bootstrap dependency and remain hardening
work; this audit must not silently label them intentional wrap:

- `lexer:ScanNumber`, `ParseSignedIntStr` and `ps_base:StrToRealVal` can exceed
  their host accumulator/exponent width on oversized numeric text. INTEGER64
  literal precision/WORD64 admission gaps are already recorded separately.
  Future overflow checking must not be weakened to preserve garbage values.
- `tc_expr`/`cg_types` host INTEGER64 folders and `tc_decl` constant/bound
  calculations can exceed the host range on pathological expressions. Exact
  constant diagnostics/width handling need their own solution; a blanket
  MATHCK- would conceal a compiler correctness bug. Gen1 C's signed DIV/MOD
  also has no zero/MIN64/-1 helper; audited compiler use guards zero and does
  not divide MIN64 by -1 on the bootstrap inputs. This is not a promise of
  pasboot safety for arbitrary out-of-subset arithmetic edge programs.
- Dynamic buffer doubling (`lexer`, `jsonutil`, `ps_base`, `bytebuf`), lexer
  INTEGER line/column counters, and aggregate layout/shadow-size products can
  outgrow their representable widths or allocations on oversized inputs.
  Those need limits/guards, not modular sizes. Existing table guards do not
  imply every layout or capacity calculation has been proved safe.
- `pretty81:IntToStr`, `cg_stmt:IntToStr255`, `cg_symbols:InitckIntText` negate
  an INTEGER32 without widening; the minimum value cannot be represented as
  a positive INTEGER32. Their ordinary bootstrap inputs do not hit this case.
  Do not disable checking to preserve a broken formatter; widen magnitude as
  `bytebuf:BufAppendInt` already does if that domain is needed.

## Pasboot policy and regression coverage

Pasboot accepts standalone `$MATHCK+`, `$MATHCK-` and numeric settings
(`$MATHCK:<signed integer>`) in either comment form, but **ignores the setting**.
Its existing Clang `-fwrapv`/result-width casts implement unchecked wrapping
`+ - *` and negation, consistent with the defined native MATHCK- results. Gen1
never claims enabled overflow protection. Other directives (including DEBUG,
PUSH and POP) remain unsupported; malformed MATHCK settings are rejected.
No WORD support, overflow checking or general DIV/MOD safety is added to
pasboot in this slice.

`bootstrap/tests/mathck_ignored.pas` pins enabled/disabled/numeric ignored
settings, native INTEGER wrapping, a representable INTEGER64 2^31 build-up,
and truncating negative division/remainder. The standard pasboot fixture suite
also checks malformed settings and retains its unsupported DEBUG probe.

`tests/mathck_bootstrap_audit.sh` (in `make test-native`) checks:

- actual source lexer flags: only the intended label expressions are disabled,
  with the loop increment and following routines still enabled;
- O0 IR from the actual `tc_expr`/`cg_decl` units: WORD16 limit and INTEGER32
  build-ups use i64 multiply/add, not i16 operations;
- numeric-label AST keys in all four generations, in both dialects (8 cells);
- high-bit numeric LABEL/GOTO/definition runtime results with both MATHCK
  settings, both dialects and O0–O3 (16 cells);
- ignored pasboot settings/wrapping at Clang O0–O3 (4 cells), plus malformed
  bare/numeric/trailing-junk rejection.

Validation for this slice: clean `make clean; make -j16 bootstrap
check-bootstrap-subset` (29 compilands; gen3/gen4 binaries byte-identical),
`make test-pasboot`, focused audit script, full `make -j16 test-native`, and
`git diff --check`. MATHCK+ overflow enforcement remains unimplemented; repeat
these gates after it ships. Frozen reference AST files are unchanged.
