{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: expected numeric constant }
(* should_fail: constant allows at most one leading sign. *)
PROGRAM P;
CONST X = --5;
BEGIN
END.
