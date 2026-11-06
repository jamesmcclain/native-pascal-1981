{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: compound_stmt needs a matching END; the "." stands where
   the next ";" or the END belongs and is reported at the missing ";". *)
PROGRAM P;
BEGIN
  X := 1
.
