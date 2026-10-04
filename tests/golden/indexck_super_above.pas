{ DIALECT: extended }
PROGRAM indexck_super_above(OUTPUT);
TYPE Cells = SUPER ARRAY [-2..*] OF INTEGER; P = ^Cells;
VAR p: P; i: INTEGER;
BEGIN
  NEW(p, 3); p^[3] := 5;
  i := 4; p^[i] := 9;
  WRITELN('unreachable')
END.
