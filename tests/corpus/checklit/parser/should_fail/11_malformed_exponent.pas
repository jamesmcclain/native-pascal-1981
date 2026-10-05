{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: exponent requires >=1 digit; 'E' with none must not crash. *)
PROGRAM P;
CONST C = 1.5E;
BEGIN
END.
