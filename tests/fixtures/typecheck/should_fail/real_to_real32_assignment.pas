{ DIALECT: extended }
PROGRAM RealToReal32Assignment;
VAR
  narrow: REAL32;
  wide: REAL;
BEGIN
  wide := 1.25;
  narrow := wide
END.
