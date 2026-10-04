{ DIALECT: extended }
PROGRAM RejectUnsafeDescriptorImport;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR p, q: PCells;
BEGIN p := NIL; q := UNSAFESUPER(PCells, p, 2, 4) END.
