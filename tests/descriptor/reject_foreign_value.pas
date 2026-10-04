{ DIALECT: extended }
PROGRAM RejectForeignValue;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
PROCEDURE Sink(src: PCells) [C]; EXTERN;
VAR p: PCells;
BEGIN p := NIL; Sink(p) END.
