{ DIALECT: extended }
PROGRAM RejectUnsafeMissingBounds;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR p: PCells; raw: CPTR;
BEGIN raw := NIL; p := UNSAFESUPER(PCells, raw, 4) END.
