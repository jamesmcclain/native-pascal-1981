{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: exponent sign with no following digits. *)
PROGRAM P;
CONST C = 1.5E+;
BEGIN
END.
