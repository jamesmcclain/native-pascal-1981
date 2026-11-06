{ A typechecker error inside an included routine names the included file. }
PROGRAM type_error(OUTPUT);
VAR n: INTEGER;
(*$INCLUDE:'type_error.inc'*)
BEGIN
  Bump;
  WRITELN(n)
END.
