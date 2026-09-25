PROGRAM indexck_guard_ir(OUTPUT);
VAR a: ARRAY[1..2] OF INTEGER; i: INTEGER;
BEGIN
  i := 1;
  a[i] := 7;
  IF FALSE THEN a[0] := 8; { checked constant: guard in a dead access }
  {$INDEXCK-} a[3] := 9; { unchecked constant: compile only; never run }
END.
