(*$INCLUDE:'conv.inc'*)
PROGRAM CONVMAIN(output);
USES CONVU (CONV);
TYPE PINT = ^INTEGER32; PREAL = ^REAL;
VAR cell: PINT; x: PREAL;
BEGIN
  NEW(cell); NEW(x); cell^ := 0; x^ := {VALUE};
  WRITELN('prefix');
  LAUNCH(CONV, 1, 1, x, cell);
  WRITELN(cell^)
END.
