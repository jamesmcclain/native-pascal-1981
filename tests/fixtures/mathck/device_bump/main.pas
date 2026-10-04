(*$INCLUDE:'bump.inc'*)
PROGRAM BUMPMAIN(output);
USES BUMPU (BUMP);
TYPE PINT = ^INTEGER32;
VAR cell: PINT;
BEGIN
  NEW(cell); cell^ := 2147483646;
  LAUNCH(BUMP, 1, 1, cell);
  WRITELN(cell^);
  LAUNCH(BUMP, 1, 1, cell);
  WRITELN(cell^)
END.
