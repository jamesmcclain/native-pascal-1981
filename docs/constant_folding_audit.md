# Integer constant DIV/MOD consumer audit

This arithmetic prerequisite changes both `FoldConstInt` implementations to
truncate DIV toward zero and give MOD the dividend's sign. It removes the
Python-floor adjustment, not the existing constant subset or adaptation rules.
Zero divisors diagnose rather than silently making an expression unfoldable.
`CheckExpr` additionally checks the divisor independently, so a dynamic dividend
cannot hide a constant zero. These rules do not depend on MATHCK.

## Typechecker (`src/tc_expr.pas`, `src/tc_decl.pas`)

- Target checking (`CheckExprForSetTarget`): the exact folded value controls
  constant range errors and assignment/argument adaptation. G22 now fits
  INTEGER at -32768; representable MIN MOD -1 is zero. Existing constant
  overflow rejection remains intact.
- Constant array indices (`CheckDesignator`): compile-time bound checks use
  the same truncating value as codegen's index rebuilding. The large negative
  index fixture checks the lower edge rather than the old floor result below it.
- Unary literal typing: its fold has no DIV/MOD itself; recursive arithmetic
  still follows the same semantics when consumed by target checks.
- CONST symbol values (`CheckDecl`): later names carry the corrected fold.
  `CheckConstOrdinalBounds` folds SUCC/PRED arguments and retains its existing
  domain checks; nested DIV/MOD does not acquire a separate rounding rule.
- CASE label checking and type/array bound resolution use expression checking
  or previously recorded CONST values, rather than another floor folder.

## Codegen (`src/cg_types.pas`, `src/cg_expr.pas`, `src/cg_expr_vector.pas`)

- `IsIntLiteralLike` / `IntLiteralValue`: all general-expression adaptation
  consumers inherit the corrected fold. The shadowed-name filter is preserved;
  a variable or user routine must not become a substituted constant.
- `CoerceForAssign`: INTEGER constants rebuilt at 8/32/64-bit targets and
  wider ordinal targets use the exact truncating value. The old wide-folding
  golden expected floor results and is intentionally corrected to -2/-1.
- `CodegenBinOp`: literal-to-wide adaptation before promotion uses the same
  fold as target checking. The focused test includes mixed-width addition
  with a negative folded remainder.
- `CodegenDesignator`: VECTOR and fixed/SUPER array constant index paths
  (including rebasing and bounds checks) all use this folder, so no local
  signed rounding adjustment remains. Fixed array reconstruction with
  `CONST N = -65537; a[N DIV 2]` is executed at O0–O3.
- `CodegenVload` / `CodegenVstore`: their constant index reconstruction uses
  `IsIntLiteralLike` plus `FoldConstInt`, preserving the shadow filter and
  bounds contracts; only the folded quotient/remainder changes.
- `SuperBoundBits`: exact INTEGER constants are preserved before i16
  materialization; dynamic and unsigned bounds keep their existing extension
  and runtime descriptor validation.
- `CodegenConstDecl` uses `IntLiteralValue`; subsequent CASE labels and array
  bounds consume the corrected CONST table. Direct parser-derived AST probes
  exercise this route and separately verify each stage's zero rejection.
  The source CONST/CASE/bound grammar admits literals, names and selected
  intrinsics, not binary arithmetic; this work does not expand that grammar.

No additional floor adjustment was found among these consumers. Compiler
self-hosting has no dependency on the old negative floor fold: a clean bootstrap
and subset check retain the gen3/gen4 byte-identical fixed point. Frozen AST
files are unchanged. Broader constant-folder width/overflow and literal
precision limitations are not solved here; enabled runtime overflow checks,
operator locations and VECTOR division safety remain separate work.
