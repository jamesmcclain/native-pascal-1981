{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: a USES clause ends with ";", as in the IBM manual and
   pasboot. *)
PROGRAM P;
USES A
BEGIN
END.
