PROGRAM P(OUTPUT);
VAR s: SET OF 0..255; i: INTEGER;
BEGIN
  i := 255; s := [250..i]; WRITELN('ok ', 255 IN s);
  i := 300; s := [250..i]; WRITELN('not reached')
END.
