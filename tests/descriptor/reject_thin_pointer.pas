{ DIALECT: extended }
PROGRAM RejectThinPointer;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     PInteger = ^INTEGER;
VAR p: PCells; thin: PInteger;
BEGIN thin := NIL; p := thin END.
