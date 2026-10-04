PROGRAM indexck_const_dead_access(OUTPUT);
CONST beyond = 5;
VAR a: ARRAY[2..4] OF INTEGER;
BEGIN
  a[2] := 7;
  IF FALSE THEN a[beyond] := 42;
  IF FALSE THEN WRITELN(a[1]);
  WRITELN('alive ', a[2])
END.
