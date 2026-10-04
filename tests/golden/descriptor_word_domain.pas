{ DIALECT: extended }
PROGRAM DescriptorWordDomain(output);
TYPE Cells = SUPER ARRAY [40000..*] OF INTEGER8; PCells = ^Cells;
VAR backing: ARRAY [40000..60000] OF INTEGER8; p: PCells; i: WORD;
BEGIN
  p := UNSAFESUPER(PCells, ADR backing, 40000, 60000);
  i := 60000; p^[i] := 7;
  WRITELN(LOWER(p^), ' ', UPPER(p^), ' ', p^[60000], ' ', backing[i])
END.
