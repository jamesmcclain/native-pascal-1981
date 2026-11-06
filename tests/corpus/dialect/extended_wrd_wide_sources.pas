{ DIALECT: extended }
{ OPT: 0 2 }
{ NEW-23: WRD of an INTEGER32/INTEGER64/WORD32/WORD64 value at run time
  was a zero-extend from i32/i64 to i16, which LLVM rejected. WRD is the
  value modulo 65536 as a WORD (IBM 11-8), unchecked even under RANGECK,
  the same value the constant folder gives: wider sources keep their low
  16 bits, INTEGER8 sign-extends (WRD of -2 is 65534 at every width),
  WORD8 zero-extends. }
PROGRAM ExtendedWrdWideSources(OUTPUT);
{$RANGECK+}
CONST
  K = WRD(70000);
  N = WRD(-2);
VAR
  i8: INTEGER8;
  i16: INTEGER;
  i32: INTEGER32;
  i64: INTEGER64;
  w8: WORD8;
  w16: WORD;
  w32: WORD32;
  w64: WORD64;
BEGIN
  i8 := -2;
  i16 := -2;
  i32 := 70000;
  i64 := -2;
  w8 := 200;
  w16 := 65000;
  w32 := 131073;
  w64 := 4294967297;
  WRITELN('integer8 ', WRD(i8));
  WRITELN('integer ', WRD(i16));
  WRITELN('integer32 ', WRD(i32), ' ', WRD(RETYPE(INTEGER32, -70000)));
  WRITELN('integer64 ', WRD(i64));
  WRITELN('word8 ', WRD(w8));
  WRITELN('word ', WRD(w16));
  WRITELN('word32 ', WRD(w32));
  WRITELN('word64 ', WRD(w64));
  IF WRD(i32) = K THEN WRITELN('WRD(i32) = CONST WRD(70000) = ', K);
  IF (WRD(i8) = N) AND (WRD(i64) = N) THEN WRITELN('every -2 is ', N)
END.
