{ probes: p1=dynamic p2=dynamic p3=dynamic p4=dynamic p5=dynamic p6=dynamic p7=dynamic p8=dynamic p9=dynamic q1=fold q2=fold q3=fold q4=fold q5=fold q6=fold q7=fold q8=dynamic q9=dynamic b1=fold b2=fold b3=fold }
PROGRAM userbuiltins;
{ User routines spelled like the folded intrinsics are ordinary calls in a
  general expression; once their scope closes the intrinsics fold again.
  HIBYTE and LOBYTE are never folded by either stage. }
CONST H = 258;
VAR p1, p2, p3, p4, p5, p6, p7, p8, p9: INTEGER32;
  q1, q2, q3, q4, q5, q6, q7, q8, q9: INTEGER32;
  b1, b2, b3: INTEGER8;
PROCEDURE Users;
  FUNCTION ORD(x: INTEGER): INTEGER; BEGIN ORD := x * 10 END;
  FUNCTION CHR(x: INTEGER): INTEGER; BEGIN CHR := x * 11 END;
  FUNCTION SUCC(x: INTEGER): INTEGER; BEGIN SUCC := x * 12 END;
  FUNCTION PRED(x: INTEGER): INTEGER; BEGIN PRED := x * 13 END;
  FUNCTION ABS(x: INTEGER): INTEGER; BEGIN ABS := x * 14 END;
  FUNCTION SQR(x: INTEGER): INTEGER; BEGIN SQR := x * 15 END;
  FUNCTION BYWORD(x, y: INTEGER): INTEGER; BEGIN BYWORD := x * y END;
  FUNCTION HIBYTE(x: INTEGER): INTEGER; BEGIN HIBYTE := x * 16 END;
  FUNCTION LOBYTE(x: INTEGER): INTEGER; BEGIN LOBYTE := x * 17 END;
BEGIN
  p1 := ORD(2) + 0;
  p2 := CHR(2) + 0;
  p3 := SUCC(2) + 0;
  p4 := PRED(2) + 0;
  p5 := ABS(-2) + 0;
  p6 := SQR(2) + 0;
  p7 := BYWORD(2, 3) + 0;
  p8 := HIBYTE(2) + 0;
  p9 := LOBYTE(2) + 0
END;
BEGIN
  Users;
  b1 := SQR(-11);
  b2 := ABS(-7);
  b3 := ORD('A');
  q1 := ORD('A') + 0;
  q2 := ORD(CHR(66)) + 0;
  q3 := SUCC(2) + 0;
  q4 := PRED(2) + 0;
  q5 := ABS(-2) + 0;
  q6 := SQR(2) + 0;
  q7 := ORD(BYWORD(1, 2)) + 0;
  q8 := HIBYTE(H) + 0;
  q9 := LOBYTE(H) + 0;
  WRITELN(p1, ' ', p2, ' ', p3, ' ', p4, ' ', p5, ' ', p6, ' ', p7, ' ', p8, ' ', p9);
  WRITELN(q1, ' ', q2, ' ', q3, ' ', q4, ' ', q5, ' ', q6, ' ', q7, ' ', q8, ' ', q9);
  WRITELN(b1, ' ', b2, ' ', b3)
END.
