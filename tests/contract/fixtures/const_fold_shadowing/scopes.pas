{ probes: p1=dynamic p2=dynamic p3=dynamic p4=fold p5=fold p6=fold p7=dynamic p8=fold p9=fold b1=fold b2=fold }
PROGRAM scopes;
{ A CONST hidden by a parameter, a VAR, a FOR variable and a deeper CONST,
  and a VAR hidden by a deeper CONST. }
CONST S = 5;
VAR p1, p2, p3, p4, p5, p6, p7, p8, p9: INTEGER32;
  a: ARRAY [1..3] OF INTEGER;
  T: INTEGER;
  b1, b2: INTEGER8;
PROCEDURE ByParam(S: INTEGER);
BEGIN
  p1 := S + 0;
  a[S] := 1
END;
PROCEDURE ByVar;
VAR S: INTEGER;
  PROCEDURE Deeper;
  CONST S = 9;
  BEGIN
    p4 := S + 0;
    b1 := S
  END;
BEGIN
  S := 2;
  p2 := S + 0;
  Deeper;
  p7 := S * 1;
  a[S] := 2
END;
PROCEDURE ByFor;
VAR S: INTEGER;
BEGIN
  FOR S := 3 TO 3 DO p3 := S + 0
END;
PROCEDURE ConstOverVar;
CONST T = 6;
BEGIN
  p5 := T + 0;
  b2 := T
END;
PROCEDURE ConstOverConst;
CONST S = 7;
BEGIN
  p6 := S + 0
END;
BEGIN
  T := 1;
  ByParam(1);
  ByVar;
  ByFor;
  ConstOverVar;
  ConstOverConst;
  p8 := S + 0;
  p9 := S - 4;
  a[p9] := 3;
  WRITELN(p1, ' ', p2, ' ', p3, ' ', p4, ' ', p5, ' ', p6, ' ', p7, ' ', p8, ' ', p9);
  WRITELN(a[1], a[2], T, ' ', b1, ' ', b2)
END.
