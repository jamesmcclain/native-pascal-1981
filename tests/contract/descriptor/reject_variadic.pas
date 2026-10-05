{ DIALECT: extended }
PROGRAM RejectVariadic;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
PROCEDURE Sink(marker: CINT) [C, VARARGS]; EXTERN;
VAR p: PCells;
BEGIN p := NIL; Sink(0, p) END.
