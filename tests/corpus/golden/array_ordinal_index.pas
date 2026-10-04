PROGRAM array_ordinal_index(OUTPUT);
TYPE Color = (r, g, b);
VAR n: ARRAY['a'..'c'] OF INTEGER; e: ARRAY[r..b] OF INTEGER; t: ARRAY[FALSE..TRUE] OF INTEGER;
    h: ARRAY[g..b] OF CHAR; u: ARRAY['x'..'z'] OF ARRAY[FALSE..TRUE] OF CHAR;
    c: CHAR; k: Color; f: BOOLEAN;
BEGIN
  FOR c := 'a' TO 'c' DO n[c] := ORD(c);
  n['b'] := n['b'] * 10;
  WRITELN(n['a'], ' ', n['b'], ' ', n['c']);
  FOR k := r TO b DO e[k] := ORD(k) + 100;
  e[g] := 7;
  WRITELN(e[r], ' ', e[g], ' ', e[b]);
  t[FALSE] := 1; t[TRUE] := 2; f := TRUE;
  WRITELN(t[FALSE], ' ', t[f], ' ', t[NOT f]);
  h[g] := 'G'; h[b] := 'B'; WRITELN(h[g], h[b]);
  FOR c := 'x' TO 'z' DO BEGIN u[c][FALSE] := c; u[c, TRUE] := CHR(ORD(c) - 32) END;
  FOR c := 'x' TO 'z' DO WRITE(u[c][FALSE], u[c][TRUE]); WRITELN;
END.
