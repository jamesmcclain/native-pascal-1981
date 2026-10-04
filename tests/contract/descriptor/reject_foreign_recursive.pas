{ DIALECT: extended }
PROGRAM RejectForeignRecursive;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     PNode = ^Node;
     Node = RECORD next: PNode; data: PCells END;
PROCEDURE Sink(src: PNode) [C]; EXTERN;
VAR n: PNode;
BEGIN n := NIL; Sink(n) END.
