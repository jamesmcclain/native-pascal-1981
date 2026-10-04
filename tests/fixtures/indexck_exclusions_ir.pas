{ DIALECT: extended }
{ Compile only: no unchecked out-of-bounds access is executed. }
{ SUPER ARRAY subscripts are now checked through the selected descriptor's
  actual upper bound (see indexck_guard_ir.sh); STRING/LSTRING indexes and
  VECTOR lanes remain excluded from host INDEXCK diagnostics. }
PROGRAM indexck_exclusions_ir(OUTPUT);
TYPE V4F = VECTOR[4] OF REAL32;
VAR s: STRING(8); l: LSTRING(8);
    lanes: V4F; buf: ARRAY[0..7] OF REAL32; i: INTEGER;
BEGIN
  i := 1;
  s[i] := 'a';
  l[i] := 'b';
  lanes[i] := lanes[0];
  lanes := VLOAD(buf, i, V4F);
  VSTORE(buf, i, lanes)
END.