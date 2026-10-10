{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: AND THEN/OR ELSE can only join the operands of an IF, WHILE or UNTIL condition, not in parentheses or another expression }
(* should_fail: AND THEN/OR ELSE cannot be part of an actual parameter. *)
PROGRAM ActualAndThen;
VAR n: INTEGER; b: BOOLEAN;
BEGIN
  n := 1;
  WRITELN((n > 0) AND THEN (n < 5))
END.
