{ DIALECT: extended }
PROGRAM RejectForeignResult;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
FUNCTION Source: PCells [C]; EXTERN;
VAR p: PCells;
BEGIN p := Source END.
