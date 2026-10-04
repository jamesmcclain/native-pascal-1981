{ DIALECT: extended }
PROGRAM DescriptorRegisterBudget(output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     Pair = RECORD first, second: PCells END;
VAR p, q: PCells; r: Pair;
FUNCTION Spill(a, b, c, d, e: INTEGER32; src: PCells; tail: INTEGER32): PCells;
BEGIN
  WRITELN(a + b + c + d + e + tail, ' ', UPPER(src^));
  Spill := src; RETURN
END;
FUNCTION SpillSret(a, b, c, d: INTEGER32; src: PCells): Pair;
VAR res: Pair;
BEGIN
  res.first := src; res.second := src; SpillSret := res
END;
BEGIN
  NEW(p, 9); p^[9] := 19;
  q := Spill(1, 2, 3, 4, 5, p, 6);
  r := SpillSret(1, 2, 3, 4, q);
  WRITELN(UPPER(r.first^), ' ', r.second^[9]);
  DISPOSE(p)
END.
