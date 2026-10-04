PROGRAM copyok;
TYPE P = RECORD x, y: INTEGER; c: CHAR END;
     V = ARRAY [1..3] OF P;
VAR g: P;
FUNCTION sum(q: P): INTEGER;
BEGIN {$INITCK+} sum := q.x + q.y {$INITCK-} END;
FUNCTION firstx(w: V): INTEGER;
BEGIN {$INITCK+} firstx := w[1].x {$INITCK-} END;
FUNCTION mk(n: INTEGER): P;
VAR t: P;
BEGIN t.x := n; t.y := n; t.c := 'm'; mk := t END;
PROCEDURE probe;
VAR a, b, e: P; v, w: V; i: INTEGER;
BEGIN
  {$INITCK+}
  a.x := 0; a.y := -32768; a.c := 'a';
  b := a;                         { checked, complete }
  v[2] := b; v[1].x := 9;         { record into element; partial array }
  {$INITCK-} w := v; {$INITCK+}   { unchecked partial copy keeps states }
  i := 2; e := w[i];              { checked copy of a complete element }
  a := a;                         { checked self-copy }
  g := e; {$INITCK-} e := g; {$INITCK+}  { untracked global round trip }
  b := mk(5);                     { untracked call result }
  {$INITCK-} i := firstx(w); {$INITCK+}  { partial value actual, transported }
  WRITELN(b.x, ' ', e.y, ' ', w[2].c, ' ', w[1].x, ' ', sum(v[2]), ' ',
          i, ' ', a.y, b.c)
END;
BEGIN probe END.
