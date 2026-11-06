{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: an IMPLEMENTATION unit's init body needs ";" between its
   statements. *)
INTERFACE;
UNIT U (Q);
PROCEDURE Q;
END;
IMPLEMENTATION OF U;
VAR X: INTEGER;
PROCEDURE Q;
BEGIN
END;
BEGIN
  X := 1
  Q
END.
