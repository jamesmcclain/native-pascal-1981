{ DIALECT: extended }
PROGRAM RejectRawExport;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR raw: CPTR; p: PCells;
BEGIN p := NIL; raw := p END.
