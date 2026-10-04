{ DIALECT: extended }
PROGRAM RejectRawImport;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR raw: CPTR; p: PCells;
BEGIN raw := NIL; p := raw END.
