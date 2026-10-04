PROGRAM oncebad;
FUNCTION next(k: INTEGER): INTEGER;
BEGIN WRITELN('next'); next := k END;
PROCEDURE probe(k: INTEGER);
VAR a: ARRAY [1..3] OF INTEGER;
BEGIN
  a[1] := 1;
  {$INITCK+} WRITELN(a[next(k)]) {$INITCK-}
END;
BEGIN probe(1); probe(2) END.
