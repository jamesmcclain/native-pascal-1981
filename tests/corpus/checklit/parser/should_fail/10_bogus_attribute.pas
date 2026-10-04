{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: expected attribute item }
(* should_fail: unrecognized attribute name (real compiler: error 310). *)
PROGRAM P;
VAR [BOGUS] x : INTEGER;
BEGIN
END.
