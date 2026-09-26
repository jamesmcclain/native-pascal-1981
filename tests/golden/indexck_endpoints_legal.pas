PROGRAM indexck_endpoints_legal(OUTPUT);
VAR a: ARRAY[2..4] OF INTEGER; i: INTEGER;
BEGIN
  i := 2; a[i] := 11;
  i := 4; a[i] := 13;
  WRITELN(a[2], ' ', a[4]);
  {$RANGECK-} WRITELN(a[{$INDEXCK-}2] + a[{$INDEXCK+}4]);
  IF a[{$INDEXCK-}2] < a[{$INDEXCK+}4] THEN WRITELN('in range')
END.
