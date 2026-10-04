{ DIALECT: extended }
PROGRAM indexck_super_const_bad_load(OUTPUT);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR p: P;
BEGIN
  NEW(p, 9);
  WRITELN(p^[1]) { valid INTEGER constant, below the declared lower }
END.
