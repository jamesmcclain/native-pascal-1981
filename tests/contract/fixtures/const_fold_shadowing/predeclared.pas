{ probes: p1=fold p2=fold p3=fold p4=fold p5=fold p6=dynamic p7=fold p8=dynamic p9=dynamic q1=fold b1=fold }
PROGRAM predeclared;
{ The predeclared maxima are constants to both folders until a user VAR,
  CONST or routine of the same spelling hides them. MAXWORD64 has no
  INTEGER64 value and folds in neither. }
CONST W = MAXWORD;
VAR p1, p2, p3, p4, p5, p6, p7, p8, p9, q1: INTEGER32;
  b1: INTEGER8;
PROCEDURE ByVar;
VAR maxint: INTEGER;
BEGIN
  maxint := 3;
  p6 := maxint + 0
END;
PROCEDURE ByConst;
CONST maxint = 4;
BEGIN
  p7 := maxint + 0;
  b1 := maxint
END;
PROCEDURE ByFunction;
  FUNCTION MaxWord: INTEGER; BEGIN MaxWord := 5 END;
BEGIN
  p8 := MaxWord + 0
END;
PROCEDURE ByParam(maxint32: INTEGER32);
BEGIN
  p9 := maxint32 + 0
END;
BEGIN
  p1 := MAXINT + 1;
  p2 := MAXWORD - 65530;
  p3 := MAXINT32 - 1;
  p4 := MAXWORD32 DIV 65536 - 65535;
  p5 := W - 65535;
  ByVar;
  ByConst;
  ByFunction;
  ByParam(6);
  q1 := MAXINT64 DIV 4294967296;
  WRITELN(p1, ' ', p2, ' ', p3, ' ', p4, ' ', p5, ' ', p6, ' ', p7, ' ', p8, ' ', p9, ' ', q1, ' ', b1)
END.
