{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: implementation_unit has no END; it ends at the period. *)
IMPLEMENTATION OF U;
CONST K = 1;
END.
