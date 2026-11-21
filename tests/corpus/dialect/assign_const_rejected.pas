{ NEW-30: assigning to or mutating a CONST is rejected in the typechecker. }
PROGRAM assign_const_rejected;
CONST
  N = 1;
  S = 'hi';
  R = 1.5;

PROCEDURE TakeVar(VAR x: INTEGER);
BEGIN
  x := 2;
END;

BEGIN
  N := 2;
  S := 'no';
  R := 2.5;
  TakeVar(N);
  FOR N := 1 TO 2 DO
    WRITELN(N);
  READ(N);
END.
