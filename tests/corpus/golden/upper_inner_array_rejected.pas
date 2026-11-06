{ DIALECT: vintage }
{ The inner index type is known to the typechecker, so a wrong
  destination is a located typecheck error, not a codegen abort. }
PROGRAM upbad(OUTPUT);
VAR a: ARRAY [1..3] OF ARRAY [1..4] OF INTEGER;
  c: CHAR;
BEGIN
  c := UPPER(a[1])
END.
