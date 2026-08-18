{ A [C] FOREIGN routine's parameter list cannot include a callback/function-
  pointer parameter (the qsort-style pattern), because the 1981 dialect (in
  both compilers) has no procedural type at all -- PROCEDURE/FUNCTION never
  appear as a type in any context, VAR declaration, parameter, or field.
  This is not a native-vs-reference C-ABI gap to close: it is a parse-time
  rejection identically in both compilers, so it has nothing to bind to.
  Documents that scope boundary the same way with_bad_pointer.pas documents
  a different one. }
PROGRAM CProcParamUnsupported(output);
PROCEDURE Apply(f: PROCEDURE(x: INTEGER); n: INTEGER) [C]; EXTERN;
BEGIN
END.
