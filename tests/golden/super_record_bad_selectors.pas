{ DIALECT: extended }
{ Each selector kind still diagnoses a genuinely invalid continuation. }
PROGRAM SuperRecordBadSelectors(OUTPUT);
TYPE Cell = RECORD x: INTEGER32 END;
     Cells = SUPER ARRAY [0..*] OF Cell;
     CellPtr = ^Cells;
VAR p: CellPtr;
BEGIN
  WRITELN(p^[0].missing);
  WRITELN(p^[0].x.missing);
  WRITELN(p^[0].x[0])
END.
