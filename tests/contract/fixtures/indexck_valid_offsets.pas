PROGRAM indexck_valid_offsets;
{$INITCK-}{$MATHCK-}
VAR a: ARRAY [0..255] OF INTEGER;
    b: ARRAY [0..65535] OF INTEGER;
    c: ARRAY [-32768..32767] OF INTEGER;
    u: WORD8; w: WORD; s: INTEGER;
BEGIN
  u := 255; w := 65535; s := 32767;
  a[u] := 11; b[w] := 22; c[s] := 33;
  WRITELN(a[u], ' ', b[w], ' ', c[s])
END.
