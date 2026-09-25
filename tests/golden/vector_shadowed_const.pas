{ DIALECT: extended }
PROGRAM vector_shadowed_const(OUTPUT);
{ A VLOAD index or vector lane index that names a variable is not a
  constant, even when a CONST of the same spelling is out of range.
  Regression guard for a review finding: both were compile-time errors. }
CONST k = 100; far = -5;
TYPE V4 = VECTOR [4] OF INTEGER32;
VAR buf: ARRAY [0..15] OF INTEGER32; v: V4;
PROCEDURE p;
VAR k, far, i: INTEGER;
BEGIN
  FOR i := 0 TO 15 DO buf[i] := i;
  k := 8; far := 2;
  v := VLOAD(buf, k, V4);
  WRITELN(v[far])
END;
BEGIN
  p
END.
