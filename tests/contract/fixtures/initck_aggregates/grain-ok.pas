PROGRAM grainok;
TYPE P = RECORD x, y: INTEGER; c: CHAR; ok: BOOLEAN END;
     Row = ARRAY [0..1] OF P;
     Grid = ARRAY [1..3] OF Row;
     Box = RECORD tag: CHAR; v: ARRAY [1..4] OF INTEGER; inner: P END;
PROCEDURE probe(k: INTEGER);
VAR a: ARRAY [1..4] OF INTEGER; r: P; g: Grid; b: Box;
    seen: ARRAY [CHAR] OF BOOLEAN; i, j: INTEGER; ch: CHAR;
BEGIN
  {$INITCK+}
  a[1] := 0; i := 2; a[i] := a[1] - 32767 - 1;
  r.x := 7; r.c := 'z'; r.ok := FALSE;
  FOR i := 1 TO 3 DO
    FOR j := 0 TO 1 DO g[i][j].y := i * 10 + j;
  g[k][1].x := g[2][0].y;
  b.v[k + 1] := 5; b.inner.c := 'n'; b.tag := b.inner.c;
  ch := 'q'; seen[ch] := TRUE;
  WRITELN(a[1], ' ', a[2], ' ', r.x, r.c, ORD(r.ok), ' ', g[3][1].y, ' ',
          g[k][1].x, ' ', b.v[k + 1], b.tag, ORD(seen['q']))
END;
BEGIN probe(1); probe(3) END.
