{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: a routine body needs ";" between its statements; a bare
   procedure call followed by another statement is not one statement. *)
PROGRAM P(OUTPUT);
PROCEDURE Q;
BEGIN
  WRITELN WRITELN
END;
BEGIN
  Q;
END.
