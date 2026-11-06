(*$INCLUDE:'convck.inc'*)
PROGRAM convck_host(output);
{ Template: gpu_orchestration.sh substitutes KERNEL, COUNT (threads),
  VALUE (thread i's argument; r and z are 0.0, so z / z is NaN) and LINES
  (result cells printed). }
USES convcku (ktrunc, kround, kmany, kinc);
VAR
  xs: ARRAY [0..63] OF REAL;
  os: ARRAY [0..127] OF INTEGER32;
  dx, dout: ADRMEM;
  r, z: REAL;
  i: INTEGER;
  count: INTEGER32;
BEGIN
  r := 0.0; z := 0.0; count := {COUNT};
  FOR i := 0 TO 63 DO xs[i] := {VALUE};
  FOR i := 0 TO 127 DO os[i] := -1;
  dx := DEVALLOC(512);
  dout := DEVALLOC(512);
  DEVCOPYTO(dx, ADR xs, 512);
  DEVCOPYTO(dout, ADR os, 512);
  WRITELN('prefix');
  LAUNCH({KERNEL}, 1, count, dx, dout, count);
  DEVCOPYFROM(ADR os, dout, 512);
  FOR i := 0 TO {LINES} - 1 DO WRITELN(os[i]);
  DEVFREE(dx);
  DEVFREE(dout)
END.
