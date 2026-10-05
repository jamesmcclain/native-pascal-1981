PROGRAM const_scope_nested(OUTPUT);
{ CONST scoping through nested routines: an inner CONST hides the enclosing
  routine's VAR (so no up-level load is needed), an outer routine's CONST
  is visible inside a nested one, siblings may reuse a name, and a nested
  FUNCTION hides a file-level CONST of its name while its parent runs. A
  WITH field hides a local CONST, and a local enumeration may reuse an
  outer CONST's name for a member. }
TYPE
  R = RECORD x: INTEGER END;
CONST
  k = 1;
  f = 100;
  Red = 50;
VAR
  r: R;

PROCEDURE Outer;
CONST k = 2;
VAR m: INTEGER;
  PROCEDURE Inner;
  CONST m = 9;
  BEGIN
    WRITELN(m, ' ', k)
  END;
  FUNCTION f: INTEGER;
  BEGIN
    f := 5
  END;
  PROCEDURE Inner2;
  CONST k = 3;
  BEGIN
    WRITELN(k)
  END;
BEGIN
  m := 4;
  Inner;
  Inner2;
  WRITELN(m, ' ', k, ' ', f)
END;

PROCEDURE Fields;
CONST x = 1;
TYPE Color = (Red, Green);
VAR c: Color;
BEGIN
  WRITELN(x);
  WITH r DO WRITELN(x);
  c := Red;
  IF c = Red THEN WRITELN(ORD(Green))
END;

PROCEDURE Shades;
TYPE Shade = (Green, Red);
BEGIN
  WRITELN(ORD(Red))
END;

BEGIN
  r.x := 8;
  Outer;
  Fields;
  Shades;
  WRITELN(k, ' ', f, ' ', Red)
END.
