{ MATHCK on/off twin (extended dialect): tests/contract/mathck_twins.sh prepends
  $MATHCK+ or $MATHCK- and requires identical output (twin_extended.out).
  Every width, scoped builtin, SADDOK-family call, VECTOR lane operation
  and reduction, and FOR loop ending at its type's maximum stays in range;
  several results land exactly on a type's minimum or maximum. }
PROGRAM TwinExtended(output);
TYPE
  V = VECTOR [4] OF INTEGER32;
  VW = VECTOR [4] OF WORD;
VAR
  i8: INTEGER8; w8: WORD8;
  i, k: INTEGER; w: WORD;
  i32, j32, m32: INTEGER32; w32: WORD32;
  i64, max64: INTEGER64; w64: WORD64;
  n, c: INTEGER; cw: WORD; ok: BOOLEAN;
  a, b, d: V; va, vb: VW;
BEGIN
  i8 := -127; i8 := i8 - 1; WRITELN('int8 ', i8, ' ', -(i8 + 1), ' ', i8 DIV 2);
  w8 := 250; w8 := w8 + 5; WRITELN('word8 ', w8, ' ', w8 DIV 16, ' ', w8 MOD 16);
  i32 := 46340; j32 := i32 * i32; WRITELN('int32 ', j32, ' ', -j32 - 1);
  i32 := -2147483647; i32 := i32 - 1; m32 := -1;
  WRITELN('int32 min ', i32, ' ', i32 MOD m32, ' ', i32 DIV 2);
  w32 := 65535; w32 := w32 * 65537; WRITELN('word32 ', w32, ' ', w32 DIV 3);
  max64 := 9223372036854775807; i64 := -max64 - 1;
  WRITELN('int64 ', max64, ' ', i64, ' ', i64 + max64, ' ', i64 MOD 10);
  w64 := 4294967295; w64 := w64 * 4294967297;
  WRITELN('word64 ', w64); w64 := w64 DIV 4294967297; WRITELN('word64 div ', w64);
  i := 32766; k := -32767;
  WRITELN('builtins ', SUCC(i), ' ', PRED(k), ' ', ABS(k), ' ', SQR(181),
          ' ', ABS(-32767), ' ', SQR(-181));
  w := 65534; WRITELN('word builtins ', SUCC(w), ' ', PRED(WRD(1)), ' ', SQR(WRD(255)));
  WRITELN('wide builtins ', SUCC(max64 - 1), ' ', ABS(-max64), ' ',
          SQR(j32 DIV 46340), ' ', PRED(i32 + 1));
  ok := SADDOK(30000, 2767, c); WRITELN('saddok ', ok, ' ', c);
  ok := SADDOK(30000, 2768, c); WRITELN('saddok ', ok, ' ', c);
  ok := SMULOK(-128, 256, c); WRITELN('smulok ', ok, ' ', c);
  ok := UADDOK(65000, 535, cw); WRITELN('uaddok ', ok, ' ', cw);
  ok := UMULOK(256, 256, cw); WRITELN('umulok ', ok, ' ', cw);
  a := VSPLAT(1000, V); b := VSPLAT(-3, V);
  a[0] := 2147483646; b[0] := 1; a[3] := -2147483647; b[3] := -1;
  d := a + b; WRITELN('vadd ', d[0], ' ', d[1], ' ', d[3]);
  d := a * VSPLAT(1, V) - b; WRITELN('vsub ', d[0], ' ', d[1], ' ', d[3]);
  d := -d; WRITELN('vneg ', d[0], ' ', d[2]);
  a := VSPLAT(1000, V); WRITELN('vsum ', VSUM(a), ' vprod ', VPROD(VSPLAT(1000, V) DIV VSPLAT(10, V)));
  va := VSPLAT(16383, VW); vb := VSPLAT(4, VW); va := va * vb + VSPLAT(3, VW);
  WRITELN('vword ', va[0], ' ', VSUM(VSPLAT(16383, VW)));
  n := 0; FOR i := 32765 TO 32767 DO n := n + i MOD 10; WRITELN('for int ', n);
  n := 0; FOR i := -32766 DOWNTO -32768 DO n := n + 1; WRITELN('for int min ', n);
  n := 0; FOR w := 65533 TO 65535 DO n := n + 1; WRITELN('for word ', n);
  n := 0; FOR i8 := 120 TO 127 DO n := n + i8; WRITELN('for int8 ', n);
  n := 0; FOR w32 := 4294967294 TO 4294967295 DO n := n + 1; WRITELN('for word32 ', n)
END.
