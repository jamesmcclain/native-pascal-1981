{ DIALECT: extended }
PROGRAM ForeignRecursiveThin;
TYPE PNode = ^Node;
     Node = RECORD next: PNode; data: INTEGER32 END;
PROCEDURE Sink(src: PNode) [C]; EXTERN;
VAR n: PNode;
BEGIN n := NIL; Sink(n) END.
