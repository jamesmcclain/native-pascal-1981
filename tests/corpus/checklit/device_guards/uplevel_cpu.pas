{ DIALECT: extended }
{ NEW-26: DEVICE routines have no static link, so a nested DEVICE routine
  that names its enclosing routine's local is a located compile error, here
  for a CPU-targeted DEVICE compiland. }
{ CHECK-FAIL: codegen: routine Inner cannot use local k of enclosing routine go in DEVICE code at line 13 column 5 }
DEVICE MODULE UplevelCpu;
VAR out_data: ARRAY [0..3] OF INTEGER32;
PROCEDURE go;
VAR k: INTEGER32;
  PROCEDURE Inner;
  BEGIN
    out_data[1] := 1;
    out_data[0] := k
  END;
BEGIN
  k := 3;
  Inner
END;
.
