{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: CONST, TYPE and VAR declarations each end with ";". *)
PROGRAM P(OUTPUT);
VAR X: INTEGER
    Y: INTEGER;
BEGIN
END.
