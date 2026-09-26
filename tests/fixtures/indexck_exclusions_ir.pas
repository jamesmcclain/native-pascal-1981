{ DIALECT: extended }
{ Compile only: no unchecked out-of-bounds access is executed. }
PROGRAM indexck_exclusions_ir(OUTPUT);
TYPE SuperInts = SUPER ARRAY[1..*] OF INTEGER;
     SuperPtr = ^SuperInts;
     V4F = VECTOR[4] OF REAL32;
VAR p: SuperPtr; s: STRING(8); l: LSTRING(8);
    lanes: V4F; buf: ARRAY[0..7] OF REAL32; i: INTEGER;
BEGIN
  i := 1;
  WRITELN(p^[i]);
  s[i] := 'a';
  l[i] := 'b';
  lanes[i] := lanes[0];
  lanes := VLOAD(buf, i, V4F);
  VSTORE(buf, i, lanes)
END.
