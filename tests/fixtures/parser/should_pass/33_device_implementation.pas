DEVICE INTERFACE;
UNIT KERNEL (add, scale);
TYPE vec = ARRAY [1..64] OF INTEGER;
PROCEDURE add (a, b: vec; n: INTEGER);
PROCEDURE scale (v: vec; k, n: INTEGER);
END;
DEVICE IMPLEMENTATION OF KERNEL;
VAR
  [SPACE(GLOBAL)] out_data: ARRAY [1..64] OF INTEGER;
  [SPACE(SHARED)] tmp: ARRAY [1..64] OF INTEGER;

PROCEDURE add (a, b: vec; n: INTEGER);
VAR i: INTEGER;
BEGIN
  FOR i := 1 TO n DO
    tmp[i] := i
END;

PROCEDURE scale (v: vec; k, n: INTEGER);
VAR i: INTEGER;
BEGIN
  FOR i := 1 TO n DO
    tmp[i] := tmp[i] + k
END;
.
