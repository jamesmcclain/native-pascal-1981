{ DIALECT: extended }
PROGRAM RejectNumericWrite(output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR pslot: P;
BEGIN pslot := NIL; WRITELN(pslot) END.
