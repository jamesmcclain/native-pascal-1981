{ DIALECT: extended }
PROGRAM VLoadOob(output);
{ VLOAD/VSTORE past the declared end of the array is a compile-time error
  for a constant index (a variable index is unchecked -- no $INDEXCK). }
TYPE V4F = VECTOR [4] OF REAL32;
VAR
  buf: ARRAY [0..7] OF REAL32;
  v: V4F;
BEGIN
  v := VLOAD(buf, 6, V4F)
END.
