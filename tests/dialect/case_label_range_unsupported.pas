{ Neither compiler lowers a CASE label range: the Python reference raises
  "Expression type RangeExpr not yet supported" from codegen, and this one
  has the matching AbortWith. Diagnose it in the typechecker, where the
  whole CASE is still in view. }
PROGRAM CaseLabelRangeUnsupported(OUTPUT);
VAR
  i: INTEGER;
BEGIN
  i := 1;
  CASE i OF
    1 .. 3: WRITELN('low')
  END
END.
