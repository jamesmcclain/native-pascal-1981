{ DIALECT: extended }
PROGRAM indexck_super_below(OUTPUT);
TYPE Cells = SUPER ARRAY [-2..*] OF INTEGER; TP = ^Cells;
VAR p: TP; i: INTEGER;
BEGIN
  NEW(p, 3); p^[-2] := 5;
  i := -3;
  WRITELN('alive ', p^[i])
END.
