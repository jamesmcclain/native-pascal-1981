{ DIALECT: extended }
PROGRAM RejectForeignVar;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
PROCEDURE Sink(VAR src: PCells) [C]; EXTERN;
VAR p: PCells;
BEGIN p := NIL; Sink(p) END.
