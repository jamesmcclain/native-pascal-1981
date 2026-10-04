{ DIALECT: extended }
PROGRAM RejectDeviceCopy;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR p: PCells; raw: CPTR;
BEGIN p := NIL; raw := NIL; DEVCOPYTO(raw, p, 0) END.
