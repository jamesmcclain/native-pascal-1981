{ DIALECT: extended }
PROGRAM RejectRetype;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR pslot: P; raw: CPTR;
BEGIN pslot := NIL; raw := RETYPE(CPTR, pslot) END.
