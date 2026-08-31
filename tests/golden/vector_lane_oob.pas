{ DIALECT: extended }
PROGRAM VectorLaneOob(output);
{ A constant lane index outside 0..n-1 is a compile-time error. A variable
  index is not range-checked (matches arrays -- no $INDEXCK machinery). }
TYPE
  V4F = VECTOR [4] OF REAL32;
VAR
  a: V4F;
BEGIN
  a[4] := 1.0
END.
