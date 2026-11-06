{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: a stray closing parenthesis must not stall the parser. *)
PROGRAM BadCompletion;
BEGIN
  NEWp1);
END.
