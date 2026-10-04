{ DIALECT: extended }
PROGRAM DescriptorUnsafeFailures(input, output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER32; PCells = ^Cells;
VAR backing: ARRAY [2..4] OF INTEGER32; p: PCells; raw: CPTR; mode: INTEGER;
BEGIN
  READ(mode); raw := ADR backing;
  { Import checks are mandatory even when scalar index guards are off. }
  (*$INDEXCK-*)
  CASE mode OF
    1: p := UNSAFESUPER(PCells, raw, 3, 4);
    2: p := UNSAFESUPER(PCells, raw, 2, MAXWORD64);
    3: p := UNSAFESUPER(PCells, NIL, 2, 4);
    4: p := UNSAFESUPER(PCells, raw + 1, 2, 4);
    5: p := UNSAFESUPER(PCells, raw, 2, 1);
    6: p := UNSAFESUPER(PCells, raw, 2, 40000)
  END;
  WRITELN('unreachable after bad import')
END.
