{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: parameter groups are separated by ";". *)
PROGRAM P(OUTPUT);
PROCEDURE Q(A: INTEGER B: INTEGER);
BEGIN
END;
BEGIN
END.
