{ INTEGER and REAL mix: integers widen to REAL, '/' is always real
  division, and TRUNC yields a 16-bit INTEGER. }
(*$INCLUDE:'testio.inc'*)
PROGRAM mixed_real(input, output);
USES testio;

VAR
  i: INTEGER;
  w: INTEGER32;
  r: REAL;

BEGIN
  i := 7;
  r := i / 2;
  WriteLabel('TRUNC(7 / 2 * 10)');
  WriteInt(TRUNC(r * 10));
  WRITELN;
  r := 0.25;
  r := r + i;
  WriteLabel('TRUNC((0.25 + 7) * 100)');
  WriteInt(TRUNC(r * 100));
  WRITELN;
  w := 100000;
  r := w * 1.5;
  WriteLabel('100000 * 1.5 > 149999.0');
  WriteBool(r > 149999.0);
  WRITELN;
  r := -2.75;
  WriteLabel('TRUNC(-2.75)');
  WriteInt(TRUNC(r));
  WRITELN;
END.
