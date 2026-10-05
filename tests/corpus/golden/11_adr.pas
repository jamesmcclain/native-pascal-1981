PROGRAM AdrTest(OUTPUT);
TYPE PINT = ^INTEGER;
VAR
  x: INTEGER;
  p: PINT;
  raw: ADRMEM;
BEGIN
  x := 42;
  p := ADR x;
  p^ := 99;
  WRITELN('x after aliased write = ', x);
  raw := ADR x;
  WRITELN('adrmem-typed ADR compiles too');
END.
