{ Gen1 deliberately ignores MATHCK, including enabled and numeric forms. }
(*$INCLUDE:'testio.inc'*)
PROGRAM MathckIgnored(input, output);
USES testio;
VAR i: INTEGER; j: INTEGER32; wide: INTEGER64; k: INTEGER;
BEGIN
  {$MATHCK+}
  i := 32767; i := i + 1; WriteInt(i); WRITELN;
  (*$MATHCK-*)
  i := -32768; i := -i; WriteInt(i); WRITELN;
  {$MATHCK:1}
  i := 300; i := i * 300; WriteInt(i); WRITELN;
  {$MATHCK:0}
  i := 0; i := i - 1; WriteInt(i); WRITELN;
  {$MATHCK:-1}
  i := -32768; i := i - 1; WriteInt(i); WRITELN;
  {$MATHCK+}
  j := 2147483647; j := j + 1; WriteInt(j); WRITELN;
  { testio.WriteInt itself cannot format MIN64; compare rather than negate
    its magnitude in that unrelated helper. }
  wide := 9223372036854775807; wide := wide + 1;
  IF wide = (-9223372036854775807 - 1) THEN WRITELN('min64 add ok')
  ELSE WRITELN('bad min64 add');
  wide := -wide;
  IF wide = (-9223372036854775807 - 1) THEN WRITELN('min64 negate ok')
  ELSE WRITELN('bad min64 negate');
  { cg_decl's INTEGER64 build-up fits: it is not intentional wraparound. }
  wide := 0;
  FOR k := 1 TO 31 DO wide := wide * 2 + 1;
  wide := wide + 1; WriteInt(wide); WRITELN;
  { No floor-division dependency in the bootstrap arithmetic. }
  i := -7; WriteInt(i DIV 2); WRITE(' '); WriteInt(i MOD 2); WRITELN;
END.
