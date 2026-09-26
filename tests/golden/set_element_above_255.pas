PROGRAM P(OUTPUT);
VAR s: SET OF 0..255; i: INTEGER;
BEGIN
  i := 255; s := [i]; WRITELN('ok ', 255 IN s);
  i := 300; s := [i]; WRITELN('not reached')
END.
