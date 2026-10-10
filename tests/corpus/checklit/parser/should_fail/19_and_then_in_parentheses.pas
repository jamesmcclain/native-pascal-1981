{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: AND THEN/OR ELSE can only join the operands of an IF, WHILE or UNTIL condition, not in parentheses or another expression }
(* should_fail: the 1981 manual says AND THEN/OR ELSE "cannot occur in parentheses". *)
PROGRAM NestedAndThen;
VAR n: INTEGER; b: BOOLEAN;
BEGIN
  n := 1;
  IF NOT ((n > 0) AND THEN (n < 5)) THEN WRITELN(1)
END.
