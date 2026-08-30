{ DIALECT: extended }
PROGRAM builtin_const_case(input, output);
{ The builtin maxima (MAXINT, MAXWORD, MAXINT32, ...) are ordinary
  identifiers the typechecker registers as real symbols with folded case,
  so a lowercase or mixed-case spelling type-checks. Codegen compared the
  raw identifier text and only knew the uppercase spelling, so `maxint`
  died with "codegen: undefined variable: maxint". Regression test for
  that gap: every spelling below must resolve. }
VAR
  i16: INTEGER;
  w16: WORD;
  i32: INTEGER32;
  w32: WORD32;
  i64: INTEGER64;
  w64: WORD64;
BEGIN
  i16 := maxint;
  w16 := maxword;
  i32 := MaxInt32;
  w32 := maxWord32;
  i64 := maxint64;
  w64 := MAXWORD64;
  WRITELN(i16);
  WRITELN(w16);
  WRITELN(i32);
  WRITELN(w32);
  WRITELN(i64);
  WRITELN(w64);
END.
