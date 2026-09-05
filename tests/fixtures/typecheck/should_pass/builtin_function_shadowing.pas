{ User routines may shadow predeclared routine names.  The native and Python
  typecheckers must resolve these declarations before builtin dispatch. }
PROGRAM P;
VAR
  r: REAL;
  n: INTEGER32;
  page_value: INTEGER;
FUNCTION SQRT(a, b: REAL): REAL;
BEGIN
  IF a > 0.0 THEN
    SQRT := SQRT(a - 1.0, b)
  ELSE
    SQRT := b
END;
FUNCTION ORD(c: CHAR): INTEGER32;
BEGIN
  ORD := 42
END;
PROCEDURE PAGE(v: INTEGER);
BEGIN
  page_value := v
END;
BEGIN
  r := SQRT(1.0, 8.0);
  n := ORD('x');
  PAGE(7)
END.
