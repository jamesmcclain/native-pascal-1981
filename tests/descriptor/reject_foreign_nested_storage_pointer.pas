{ DIALECT: extended }
PROGRAM RejectForeignNestedStoragePointer;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     Holder = RECORD p: PCells END; PHolder = ^Holder;
     Envelope = RECORD slot: PHolder END;
PROCEDURE Sink(src: Envelope) [C]; EXTERN;
VAR e: Envelope;
BEGIN e.slot := NIL; Sink(e) END.
