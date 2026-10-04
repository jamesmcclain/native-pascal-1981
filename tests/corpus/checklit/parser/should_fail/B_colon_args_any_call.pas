{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* The same colon syntax on a call that is not WRITE/WRITELN is rejected:
   field widths belong to WRITE and WRITELN only. *)
PROGRAM P;
PROCEDURE FOO(a, b, c : INTEGER);
BEGIN
END;
BEGIN
  FOO(1:2:3)
END.
