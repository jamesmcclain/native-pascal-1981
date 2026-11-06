{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: OTHERWISE outside CASE must not stall the parser. *)
PROGRAM StrayOtherwise;
BEGIN
  x := 1;
  OTHERWISE x := 2;
END.
