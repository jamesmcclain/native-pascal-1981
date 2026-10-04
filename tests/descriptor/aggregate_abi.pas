{ DIALECT: extended }
PROGRAM DescriptorAggregateABI;
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; PCells = ^Cells;
     Pair = RECORD first, second: PCells END;
VAR pairslot: Pair;
PROCEDURE TakePair(src: Pair);
BEGIN pairslot := src END;
FUNCTION ReturnPair(src: Pair): Pair;
BEGIN ReturnPair := src END;
BEGIN
  pairslot.first := NIL; pairslot.second := NIL;
  TakePair(pairslot); pairslot := ReturnPair(pairslot)
END.
