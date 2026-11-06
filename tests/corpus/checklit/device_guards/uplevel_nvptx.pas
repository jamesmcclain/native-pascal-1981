{ DIALECT: extended }
{ CHECK-FLAGS: --emit-ptx --device-triple nvptx64-nvidia-cuda }
{ NEW-26: the same rejection for NVPTX, for a parameter of the enclosing
  routine. }
{ CHECK-FAIL: codegen: routine Inner cannot use parameter n of enclosing routine Fill in DEVICE code at line 11 column 5 }
DEVICE MODULE UplevelNvptx;
VAR out_data: ARRAY [0..3] OF INTEGER32;
PROCEDURE Fill(n: INTEGER32);
  PROCEDURE Inner;
  BEGIN
    out_data[0] := n
  END;
BEGIN
  Inner
END;
PROCEDURE go;
BEGIN
  Fill(3)
END;
.
