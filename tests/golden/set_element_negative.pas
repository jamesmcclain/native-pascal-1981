PROGRAM P(OUTPUT);
VAR s: SET OF 0..255; i: INTEGER;
BEGIN
  i := 0; s := [i]; WRITELN('ok ', 0 IN s);
  i := -1; s := [1, i]; WRITELN('not reached')
END.
