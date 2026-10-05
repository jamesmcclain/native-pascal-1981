PROGRAM onceok;
TYPE R = RECORD x, y: INTEGER END;
VAR calls: INTEGER;
FUNCTION next: INTEGER;
BEGIN calls := calls + 1; next := 1 + calls MOD 2 END;
PROCEDURE bump(VAR n: INTEGER);
BEGIN n := n + 1 END;
PROCEDURE probe;
VAR a: ARRAY [1..2] OF INTEGER; r, s: ARRAY [1..2] OF R; y: INTEGER;
BEGIN
  {$INITCK+}
  a[1] := 0; a[2] := 0; s[1].x := 1; s[1].y := 2; s[2] := s[1];
  a[next] := 5; y := a[next]; READ(a[next]); bump(a[next]);
  WITH r[next] DO BEGIN x := 3; y := 4 END;
  r[next] := s[next];
  {$INDEXCK-} y := y + a[next]; {$INDEXCK+}
  WRITELN(y, ' ', a[1], ' ', a[2], ' ', r[1].x + r[2].x)
  {$INITCK-}
END;
BEGIN calls := 0; probe; WRITELN(calls) END.
