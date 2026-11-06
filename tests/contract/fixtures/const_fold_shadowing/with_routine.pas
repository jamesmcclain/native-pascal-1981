{ probes: p1=dynamic p2=dynamic p3=fold p4=dynamic p5=fold p6=dynamic b1=fold b2=fold }
PROGRAM withroutine;
{ A CONST hidden by a WITH field, by a nested function (called, not
  folded) and by a local VAR of a function; the CONST is
  visible again once each scope closes. A CONST evaluated before its
  operand was hidden keeps its value. }
CONST S = 5; K = SUCC(S);
TYPE R = RECORD S: INTEGER END;
VAR p1, p2, p3, p4, p5, p6: INTEGER32;
  rec: R;
  b1, b2: INTEGER8;
  a: ARRAY [1..3] OF INTEGER;
PROCEDURE Calls;
  FUNCTION S: INTEGER;
  BEGIN S := 3 END;
BEGIN
  p2 := S + 0;
  a[S] := 7
END;
FUNCTION Twice(n: INTEGER): INTEGER;
VAR S: INTEGER;
BEGIN
  S := n;
  p4 := S * 2;
  p5 := K + 0;
  b1 := K;
  Twice := n * 2
END;
BEGIN
  rec.S := 2;
  WITH rec DO
  BEGIN
    p1 := S + 0;
    a[S] := 1
  END;
  p3 := S + 0;
  b2 := S;
  Calls;
  p6 := Twice(1) + K - p4;
  WRITELN(p1, ' ', p2, ' ', p3, ' ', p4, ' ', p5, ' ', p6);
  WRITELN(a[2], a[3], ' ', b1, ' ', b2)
END.
