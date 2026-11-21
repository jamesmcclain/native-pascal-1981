{ DIALECT: vintage extended }
{ NEW-39: a plain WORD value (or WORD subrange) is compatible with a
  SET OF 0..255 (or numeric set constructor) in IN. Values >= 256,
  including > 32767, evaluate to FALSE without sign-extension wraparound. }
PROGRAM WordInSet(OUTPUT);
VAR
  s: SET OF 0..255;
  w: WORD;
  sub: WRD(0)..255;
BEGIN
  s := [0, 7, 200, 255];
  w := WRD(0);
  WRITELN(w IN s);
  w := WRD(7);
  WRITELN(w IN s);
  w := WRD(200);
  WRITELN(w IN s);
  w := WRD(255);
  WRITELN(w IN s);
  w := WRD(256);
  WRITELN(w IN s);
  w := 40000;
  WRITELN(w IN s);
  WRITELN(w IN [0, 7, 255]);
  w := 65535;
  WRITELN(w IN s);
  sub := WRD(200);
  WRITELN(sub IN s)
END.
