{ DIALECT: extended }
PROGRAM RejectNumericRead(input);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR pslot: P;
BEGIN READ(pslot) END.
