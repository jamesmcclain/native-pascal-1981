{ DIALECT: extended }
PROGRAM indexck_super_const_bad_store(OUTPUT);
TYPE Cells = SUPER ARRAY [-2..*] OF INTEGER; P = ^Cells;
VAR p: P;
BEGIN
  NEW(p, 3);
  p^[7] := 1; { valid INTEGER constant, above the actual upper }
  WRITELN('unreachable')
END.
