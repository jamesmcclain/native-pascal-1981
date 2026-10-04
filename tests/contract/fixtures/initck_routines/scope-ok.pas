PROGRAM scopeok;
TYPE R = RECORD f, g: INTEGER END;
{$INITCK+}
PROCEDURE outer(k: INTEGER; VAR vr: R);
VAR x, f, u: INTEGER; r, s: R; b: BOOLEAN;
  PROCEDURE inner(x: INTEGER);
  VAR k: INTEGER;
    FUNCTION deeper(k: INTEGER): INTEGER;
    VAR x: INTEGER;
    BEGIN x := k * 2; deeper := x END;
  BEGIN k := deeper(x); WRITELN(k) END;
BEGIN
  {$INITCK-} r.f := 10; r.g := 20; s.g := 5; f := 3; {$INITCK+}
  WITH r DO BEGIN x := {$INITCK-} g {$INITCK+} + k; f := 11 END;
  WITH r, s DO BEGIN u := x + 1; b := u > x END;
  WITH vr DO BEGIN x := x + 100; g := x END;
  WRITELN(x, ' ', f, ' ', u, ' ', ORD(b));
  inner(x)
END;
{$INITCK-}
VAR rec: R;
BEGIN outer(1, rec); WRITELN(rec.g) END.
