{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-26: a nested routine fills its enclosing FUNCTION's large RECORD
  result (returned through a hidden result pointer) from a large value
  formal (passed by a private copy), with the FUNCTION's local as its FOR
  control variable. }
PROGRAM uplevel_big_result(OUTPUT);
TYPE Big = RECORD a: ARRAY [1..20] OF INTEGER; n: INTEGER; END;
FUNCTION Make(seed: Big): Big;
VAR k: INTEGER;
  PROCEDURE Fill;
  BEGIN
    FOR k := 1 TO 20 DO Make.a[k] := seed.a[k] * 2;
    Make.n := seed.n + 1;
  END;
BEGIN
  Fill;
END;
VAR b, c: Big; i: INTEGER;
BEGIN
  FOR i := 1 TO 20 DO b.a[i] := i;
  b.n := 7;
  c := Make(b);
  WRITELN(c.a[1], ' ', c.a[20], ' ', c.n);
END.
