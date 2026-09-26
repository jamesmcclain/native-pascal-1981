PROGRAM P(OUTPUT);
VAR s: SET OF 0..255; i: INTEGER;
BEGIN
  i := 0; s := [i..5]; WRITELN('ok ', 0 IN s);
  i := -1; s := [i..5]; WRITELN('not reached')
END.
