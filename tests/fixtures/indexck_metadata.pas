PROGRAM IndexMetadata(output);
TYPE
  Row = ARRAY [0..2] OF INTEGER;
  Matrix = ARRAY [0..2] OF Row;
  Rec = RECORD x: INTEGER END;
VAR
  a: Row;
  m: Matrix;
  records: ARRAY [0..2] OF Rec;
  p: ^Row;
  i: INTEGER;
PROCEDURE Consume(x: INTEGER);
BEGIN END;
BEGIN
  i := 0;
  a[0] := 1;
  {$RANGECK-}
  a[1] := a[{$INDEXCK-}0];
  {$RANGECK+}
  i := a[0];
  i := a[{$INDEXCK+}0 + a[{$INDEXCK-}1]];
  m[{$INDEXCK+}0, {$INDEXCK-}1] := m[{$INDEXCK+}1][{$INDEXCK-}0];
  Consume(a[{$INDEXCK+}0] + a[{$INDEXCK-}1]);
  IF a[{$INDEXCK+}0] = a[{$INDEXCK-}1] THEN i := 0;
  WHILE a[{$INDEXCK+}0] < 0 DO i := a[{$INDEXCK-}1];
  REPEAT i := a[{$INDEXCK+}0] UNTIL a[{$INDEXCK-}1] = 0;
  FOR i := a[{$INDEXCK+}0] TO a[{$INDEXCK-}1] DO Consume(i);
  WITH records[{$INDEXCK+}0] DO x := a[{$INDEXCK-}1];
  i := p^[{$INDEXCK+}0];
  {$PUSH}{$INDEXCK-}
  i := a[0];
  {$POP}
  i := a[0];
  i := a[0 {$INDEXCK-} + 1];
  i := a[0]
END.
