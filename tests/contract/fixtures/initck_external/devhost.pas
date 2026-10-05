{ DIALECT: extended }
(*$INCLUDE:'kinc.inc'*)
PROGRAM DEVHOST(output);
USES BUMPU (BUMP);
TYPE PINT = ^INTEGER;
PROCEDURE probe;
VAR cell: PINT; a, b: ARRAY [1..2] OF INTEGER; d: ADRMEM; grid, nbytes: INTEGER;
BEGIN
  {$INITCK+}
  NEW(cell); grid := 2;
  LAUNCH(BUMP, grid, 3, cell);
  WRITELN(cell^);
  a[1] := 4; a[2] := 5; nbytes := 4;
  d := DEVALLOC(nbytes); DEVCOPYTO(d, ADR a, nbytes); DEVCOPYFROM(ADR b, d, nbytes); DEVFREE(d);
  WRITELN(b[1] + b[2])
  {$INITCK-}
END;
BEGIN probe END.
