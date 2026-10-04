{ DIALECT: extended }
PROGRAM RejectArithmetic;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
VAR p: PCells;
BEGIN p := NIL; p := p + 1 END.
