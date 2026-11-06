{ probes: p1=dynamic p2=dynamic p3=dynamic p4=dynamic p5=dynamic p6=dynamic p7=fold b1=fold }
PROGRAM enums;
{ An enumeration member, and a CONST computed from one, is not an integer
  constant to either folder: operations on them are checked at run time
  (tests/contract/mathck_scalar.sh). Codegen used to fold them where the
  typechecker did not: under MATHCK- the index ORD(blue) * 20000 wraps to
  -25536 at run time, but codegen indexed with the folded 40000 and failed
  the bounds check. A VAR or parameter spelled like a member hides it. A
  CHAR CONST next to them still folds. }
TYPE Col = (red, green, blue);
CONST G = green; B = ORD(blue); A = 'A';
VAR p1, p2, p3, p4, p5, p6, p7: INTEGER32;
  b1: INTEGER8;
  arr: ARRAY [-30000..-20000] OF INTEGER;
PROCEDURE Hide(green: INTEGER);
BEGIN
  p3 := green + 0
END;
PROCEDURE HideMember;
VAR blue: Col;
BEGIN
  blue := red;
  p5 := ORD(blue) + 0
END;
BEGIN
  p1 := ORD(green) + 32766;
  p2 := ORD(G) + 1;
  Hide(40);
  p4 := B * 10;
  HideMember;
  p6 := ORD(SUCC(red)) + ORD(PRED(blue));
  p7 := ORD(A) + 32767;
  b1 := ORD(A);
  {$MATHCK-} arr[ORD(blue) * 20000] := 7; {$MATHCK+}
  WRITELN(p1, ' ', p2, ' ', p3, ' ', p4, ' ', p5, ' ', p6, ' ', p7, ' ', b1, ' ', arr[-25536])
END.
