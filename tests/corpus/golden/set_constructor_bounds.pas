PROGRAM SetConstructorBounds(OUTPUT);
{ Elements and nonempty range endpoints must be in 0..255; an empty
  (reversed) range adds nothing, so its endpoints are not checked. }
VAR
  s: SET OF 0..255;
  cs: SET OF CHAR;
  lo, hi: INTEGER;
  c: CHAR;
BEGIN
  lo := 0;
  hi := 255;
  s := [lo..hi];
  WRITELN('full ', 0 IN s, ' ', 255 IN s);
  s := [lo, hi];
  WRITELN('edges ', 0 IN s, ' ', 128 IN s, ' ', 255 IN s);
  lo := 300;
  hi := 0;
  s := [lo..hi];
  WRITELN('reversed high ', s = []);
  lo := 5;
  hi := -1;
  s := [lo..hi];
  WRITELN('reversed low ', s = []);
  lo := 300;
  hi := -300;
  s := [lo..hi, 7];
  WRITELN('reversed both ', 7 IN s, ' ', s = [7]);
  c := CHR(255);
  cs := [c, 'A'..'C'];
  WRITELN('char ', CHR(255) IN cs, ' ', 'B' IN cs)
END.
