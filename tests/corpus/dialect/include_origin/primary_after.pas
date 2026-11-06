{ An error in the primary file after an include keeps the primary file's
  own line numbers and carries no file name: the lexer resumes the parent's
  position when the included file ends. }
PROGRAM primary_after(OUTPUT);
VAR n: INTEGER;
(*$INCLUDE:'type_ok.inc'*)
BEGIN
  Bump;
  n := 'not a number';
  WRITELN(n)
END.
