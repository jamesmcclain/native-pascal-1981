{ A CASE label must have the selector's type. Both compilers reject this, with
  different wording -- the reference in the typechecker ("CASE label type CHAR
  is incompatible with selector type INTEGER"), the native one in codegen --
  so what is pinned here is the rejection, not the phrasing. }
PROGRAM CaseLabelTypeMismatch(OUTPUT);
VAR
  i: INTEGER;
BEGIN
  i := 1;
  CASE i OF
    'a': WRITELN('a')
  END;
END.
