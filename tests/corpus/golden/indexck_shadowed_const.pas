{ DIALECT: extended }
PROGRAM indexck_shadowed_const(OUTPUT);
{ A checked INTEGER index that names a CONST wider than 16 bits must not be
  folded when a variable or user routine of the same spelling is visible:
  the access uses the live value, and so does the bounds check. Regression
  guard for a review finding: a[big] read a[40000] and ORD(40000) was folded to 40000. }
CONST big = 40000;
VAR a: ARRAY [0..50000] OF INTEGER;
PROCEDURE Local;
VAR big: INTEGER;
BEGIN
  big := 5;
  WRITELN(a[big])
END;
PROCEDURE Declares;
CONST huge = 45000;
BEGIN
  WRITELN(a[huge])
END;
PROCEDURE Other;
VAR huge: INTEGER;
BEGIN
  huge := 6;
  WRITELN(a[huge])
END;
FUNCTION ORD(x: INTEGER32): INTEGER;
BEGIN
  ORD := 8
END;
BEGIN
  a[5] := 7; a[6] := 8; a[8] := 11; a[40000] := 9; a[45000] := 10;
  Local;
  Declares;
  Other;
  WRITELN(a[ORD(40000)])
END.
