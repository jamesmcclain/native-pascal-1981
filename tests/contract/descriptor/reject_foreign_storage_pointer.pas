{ DIALECT: extended }
PROGRAM RejectForeignStoragePointer;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     Holder = RECORD p: PCells END; PHolder = ^Holder;
PROCEDURE Sink(slot: PHolder) [C]; EXTERN;
VAR h: PHolder;
BEGIN h := NIL; Sink(h) END.
