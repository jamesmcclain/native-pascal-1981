{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: expected statement }
(* should_fail: compound_stmt needs a matching END. *)
PROGRAM P;
BEGIN
  X := 1
.
