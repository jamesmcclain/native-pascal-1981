{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: proc body must be followed by a required ";". *)
PROGRAM P;
PROCEDURE Q;
BEGIN
END
BEGIN
END.
