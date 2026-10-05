{ DIALECT: extended }
{ CHECK-STAGES: lexer parser typechecker }
{ CHECK-FAIL: Cannot assign incompatible type without narrowing: narrow }
PROGRAM RealToReal32Assignment;
VAR
  narrow: REAL32;
  wide: REAL;
BEGIN
  wide := 1.25;
  narrow := wide
END.
