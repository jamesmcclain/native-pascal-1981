{ DIALECT: extended }
PROGRAM indexck_super_nil_store(OUTPUT);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR p: P;
BEGIN
  p := NIL;
  p^[2] := 5;
  WRITELN('unreachable')
END.
