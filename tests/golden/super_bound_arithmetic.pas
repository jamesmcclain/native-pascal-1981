{ DIALECT: extended }
{ LOWER and UPPER of a SUPER ARRAY pointer are both INTEGER64 values, so
  they combine with each other and with other INTEGER64 operands. }
PROGRAM SuperBoundArithmetic(OUTPUT);
TYPE
  Cells = SUPER ARRAY [1..*] OF INTEGER;
  CellPtr = ^Cells;
VAR
  p: CellPtr;
  n: INTEGER64;
BEGIN
  NEW(p, 3);
  n := LOWER(p^);
  WRITELN(n);
  WRITELN(LOWER(p^) + UPPER(p^));
  WRITELN(UPPER(p^) - LOWER(p^) + 1);
  n := n + LOWER(p^);
  WRITELN(n);
  DISPOSE(p)
END.
