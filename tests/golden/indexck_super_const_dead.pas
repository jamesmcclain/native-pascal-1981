{ DIALECT: extended }
PROGRAM indexck_super_const_dead(OUTPUT);
CONST beyond = 12;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR p: P;
BEGIN
  NEW(p, 9); p^[2] := 7;
  IF FALSE THEN p^[beyond] := 42;   { checked, but never executed }
  IF FALSE THEN WRITELN(p^[0]);
  WRITELN('alive ', p^[2]);
  DISPOSE(p)
END.
