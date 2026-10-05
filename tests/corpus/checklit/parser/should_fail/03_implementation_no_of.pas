{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: implementation_unit requires OF identifier. *)
IMPLEMENTATION;
CONST K = 1;
.
