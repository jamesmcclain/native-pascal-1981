{ DIALECT: vintage extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: the statements after OTHERWISE are separated by ";"
   (NEW-19), as in BEGIN..END. *)
PROGRAM P(OUTPUT);
VAR X: INTEGER;
BEGIN
  X := 3;
  CASE X OF
    1: WRITELN('one');
  OTHERWISE
    WRITELN('other')
    WRITELN(X)
  END
END.
