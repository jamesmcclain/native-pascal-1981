{ A parser error in the primary file after an include keeps the primary
  file's own line numbers and carries no file name. }
PROGRAM parser_primary_after(OUTPUT);
VAR n: INTEGER;
(*$INCLUDE:'type_ok.inc'*)
BEGIN
  Bump;
  n := (1 + 2;
  WRITELN(n)
END.
