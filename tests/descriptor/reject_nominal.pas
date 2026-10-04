{ DIALECT: extended }
PROGRAM RejectNominal;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER;
     P = ^Cells; Q = ^Cells;
VAR pslot: P; qslot: Q;
BEGIN qslot := NIL; pslot := qslot END.
