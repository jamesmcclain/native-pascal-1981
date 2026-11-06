{ probes: p1=fold p2=fold p3=dynamic p4=dynamic p5=fold b1=fold b2=fold }
PROGRAM constcontext;
{ In a constant expression -- a CONST value or a bound -- ORD, CHR, SUCC
  and PRED are the intrinsics even where user routines of those names are
  visible (ParseConstant admits them by spelling; docs/dialect_notes.md),
  and both folders give the CONST that value. In a general expression the
  same spellings call the user routines. }
FUNCTION ORD(x: INTEGER): INTEGER; BEGIN ORD := x * 10 END;
FUNCTION CHR(x: INTEGER): CHAR; BEGIN CHR := 'Z' END;
FUNCTION SUCC(x: INTEGER): INTEGER; BEGIN SUCC := x * 12 END;
CONST K = ORD(5); C = CHR(66); N = SUCC(3);
TYPE A = ARRAY [CHR(65)..CHR(70)] OF INTEGER;
VAR p1, p2, p3, p4, p5: INTEGER32;
  v: A;
  b1, b2: INTEGER8;
BEGIN
  p1 := K + 0;
  p2 := N * 2;
  p3 := ORD(5) + 0;
  p4 := SUCC(3) + 0;
  p5 := K + N;
  b1 := K;
  b2 := N;
  v[C] := 1;
  WRITELN(p1, ' ', p2, ' ', p3, ' ', p4, ' ', p5, ' ', C, ' ', CHR(66));
  WRITELN(LOWER(v), UPPER(v), v[C], ' ', b1, ' ', b2)
END.
