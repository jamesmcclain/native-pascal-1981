{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: a nested BEGIN..END needs ";" between its statements. *)
PROGRAM P(OUTPUT);
VAR X: INTEGER;
BEGIN
  IF TRUE THEN
  BEGIN
    X := 1
    X := 2
  END;
END.
