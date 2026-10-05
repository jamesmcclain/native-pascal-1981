{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: module_block has declarations only, no compound_stmt. *)
MODULE M;
BEGIN
END.
