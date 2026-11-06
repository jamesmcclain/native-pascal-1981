{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: CASE arms are separated by ";". *)
PROGRAM P(OUTPUT);
VAR X: INTEGER;
BEGIN
  X := 1;
  CASE X OF
    1: WRITELN('one')
    2: WRITELN('two')
  END;
END.
