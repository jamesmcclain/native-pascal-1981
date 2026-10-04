{ DIALECT: extended }
PROGRAM RejectForeignAggregate;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     Holder = RECORD slots: ARRAY [0..1] OF PCells END;
PROCEDURE Sink(src: Holder) [C]; EXTERN;
VAR h: Holder;
BEGIN h.slots[0] := NIL; h.slots[1] := NIL; Sink(h) END.
