{ DIALECT: extended }
PROGRAM RejectUnsafeFixedPointer;
TYPE Cells = ARRAY [2..4] OF INTEGER; PCells = ^Cells;
VAR p: PCells; raw: CPTR;
BEGIN raw := NIL; p := UNSAFESUPER(PCells, raw, 2, 4) END.
