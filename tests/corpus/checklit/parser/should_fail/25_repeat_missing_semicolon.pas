{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: Expected token match failed. Expected: }
(* should_fail: REPEAT..UNTIL needs ";" between its statements. *)
PROGRAM P(OUTPUT);
VAR X: INTEGER;
BEGIN
  REPEAT
    X := 1
    X := 2
  UNTIL X = 2;
END.
