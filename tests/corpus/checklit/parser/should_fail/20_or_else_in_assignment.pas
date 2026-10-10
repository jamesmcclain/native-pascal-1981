{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: AND THEN/OR ELSE can only join the operands of an IF, WHILE or UNTIL condition, not in parentheses or another expression }
(* should_fail: AND THEN/OR ELSE belong only to an IF, WHILE or UNTIL condition. *)
PROGRAM AssignOrElse;
VAR n: INTEGER; b: BOOLEAN;
BEGIN
  n := 1;
  b := (n > 0) OR ELSE (n < 5)
END.
