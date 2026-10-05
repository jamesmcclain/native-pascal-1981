{ INTEGER is 16 bits and wraps; wider operands widen the operation. }
(*$INCLUDE:'testio.inc'*)
PROGRAM int16_wrap(input, output);
USES testio;

VAR
  i, j: INTEGER;
  w: INTEGER32;
  big: INTEGER64;
  k: INTEGER32;

BEGIN
  i := 32767;
  i := i + 1;
  WriteLabel('32767 + 1');
  WriteInt(i);
  WRITELN;
  i := 300;
  j := i * 300;
  WriteLabel('300 * 300 in INTEGER');
  WriteInt(j);
  WRITELN;
  w := i * 300;
  WriteLabel('300 * 300 assigned to INTEGER32');
  WriteInt(w);
  WRITELN;
  w := 300;
  w := w * i;
  WriteLabel('INTEGER32 * INTEGER');
  WriteInt(w);
  WRITELN;
  w := 2147483647;
  w := w + 1;
  WriteLabel('INTEGER32 wrap');
  WriteInt(w);
  WRITELN;
  { 2^31 by repeated INTEGER64 multiply-add, as cg_decl.pas computes it }
  big := 0;
  FOR k := 1 TO 31 DO
    big := big * 2 + 1;
  big := big + 1;
  WriteLabel('2^31');
  WriteInt(big);
  WRITELN;
  i := -7;
  WriteLabel('-7 DIV 2, -7 MOD 2');
  WriteInt(i DIV 2);
  WRITE(' ');
  WriteInt(i MOD 2);
  WRITELN;
END.
