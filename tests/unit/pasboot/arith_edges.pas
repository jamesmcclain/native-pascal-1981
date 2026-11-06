{ Unchecked wrapping is defined C, not undefined behaviour: MIN DIV -1 and
  MIN MOD -1 at every width, + - * and negation past each width's range,
  and a FOR loop up to the INTEGER64 maximum. tests/unit/pasboot.sh also
  compiles this fixture without -fwrapv under -fsanitize=undefined. }
(*$INCLUDE:'testio.inc'*)
PROGRAM arith_edges(input, output);
USES testio;
CONST MinI64 = -9223372036854775807 - 1;
VAR
  i, m: INTEGER;
  w, wm: INTEGER32;
  g, gm, steps: INTEGER64;

PROCEDURE Check(ok: BOOLEAN; what: Str255);
BEGIN
  IF ok THEN WriteLabel(what) ELSE BEGIN WRITE('BAD '); WriteLabel(what) END;
  WRITELN;
END;

BEGIN
  m := -1;
  i := -32767 - 1;
  WriteLabel('INTEGER MIN DIV -1'); WriteInt(i DIV m); WRITELN;
  WriteLabel('INTEGER MIN MOD -1'); WriteInt(i MOD m); WRITELN;
  WriteLabel('INTEGER -MIN'); WriteInt(-i); WRITELN;
  wm := -1;
  w := -2147483647 - 1;
  WriteLabel('INTEGER32 MIN DIV -1'); WriteInt(w DIV wm); WRITELN;
  WriteLabel('INTEGER32 MIN MOD -1'); WriteInt(w MOD wm); WRITELN;
  WriteLabel('INTEGER32 -MIN'); WriteInt(-w); WRITELN;
  WriteLabel('INTEGER32 MIN - 1'); WriteInt(w - 1); WRITELN;
  w := 65536;
  WriteLabel('INTEGER32 65536 * 65536'); WriteInt(w * w); WRITELN;
  w := 46341;
  WriteLabel('INTEGER32 46341 * 46341'); WriteInt(w * w); WRITELN;
  gm := -1;
  g := MinI64;
  Check(g DIV gm = MinI64, 'INTEGER64 MIN DIV -1 = MIN');
  Check(g MOD gm = 0, 'INTEGER64 MIN MOD -1 = 0');
  Check(-g = MinI64, 'INTEGER64 -MIN = MIN');
  Check(g - 1 = 9223372036854775807, 'INTEGER64 MIN - 1 = MAX');
  g := 4294967296;
  Check(g * g = 0, 'INTEGER64 2^32 * 2^32 = 0');
  g := 3037000500;
  Check(g * g = -9223372036709301616, 'INTEGER64 3037000500^2 wraps');
  i := 300;
  WriteLabel('INTEGER 300 * 300'); WriteInt(i * i); WRITELN;
  { A FOR loop whose limit is the maximum stops there. }
  steps := 0;
  FOR g := 9223372036854775805 TO 9223372036854775807 DO steps := steps + 1;
  WriteLabel('FOR to MAX64 steps'); WriteInt(steps); WRITELN;
  steps := 0;
  FOR g := MinI64 + 2 DOWNTO MinI64 DO steps := steps + 1;
  WriteLabel('FOR DOWNTO MIN64 steps'); WriteInt(steps); WRITELN;
  { Truncating division still holds for ordinary operands. }
  i := -7; m := 2;
  WriteLabel('-7 DIV 2, -7 MOD 2'); WriteInt(i DIV m); WRITE(' '); WriteInt(i MOD m); WRITELN;
  w := 7; wm := -2;
  WriteLabel('7 DIV -2, 7 MOD -2'); WriteInt(w DIV wm); WRITE(' '); WriteInt(w MOD wm); WRITELN;
END.
