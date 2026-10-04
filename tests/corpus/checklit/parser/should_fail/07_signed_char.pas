{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: expected numeric constant }
(* should_fail: sign prefix applies to numeric constants only, not char. *)
PROGRAM P;
CONST C = -'A';
BEGIN
END.
