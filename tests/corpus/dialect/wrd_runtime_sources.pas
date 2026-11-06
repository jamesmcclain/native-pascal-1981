{ DIALECT: vintage extended }
{ NEW-23: WRD at run time is its argument's value modulo 65536 as a
  WORD (IBM 11-8), unchecked, the same value the constant folder gives
  in a CONST. An enumeration value is 32 bits wide in the generated code,
  so WRD of an enumeration variable was a zero-extend to a narrower type
  that LLVM rejected. Every vintage ordinal source is covered, under
  RANGECK too: WRD is never range-checked. }
PROGRAM WrdRuntimeSources(OUTPUT);
{$RANGECK+}
CONST
  M = WRD(-2);
  G = WRD('B');
TYPE
  Color = (red, green, blue);
  Small = 1..10;
  Hues = green..blue;
VAR
  c: Color;
  h: Hues;
  s: Small;
  ch: CHAR;
  bo: BOOLEAN;
  i: INTEGER;
  w: WORD;
BEGIN
  c := blue;
  h := green;
  s := 7;
  ch := 'A';
  bo := TRUE;
  i := -2;
  w := 65535;
  WRITELN('enum ', WRD(c), ' ', WRD(h), ' ', WRD(green));
  WRITELN('subrange ', WRD(s));
  WRITELN('char ', WRD(ch), ' boolean ', WRD(bo));
  WRITELN('integer ', WRD(i), ' ', WRD(-32768), ' ', WRD(32767));
  WRITELN('word ', WRD(w));
  IF WRD(i) = M THEN WRITELN('WRD(i) = CONST WRD(-2) = ', M);
  WRITELN('const char ', G)
END.
