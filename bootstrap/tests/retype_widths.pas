{ RETYPE between integer types: narrowing keeps the low bytes and widening
  sign-extends, as the native compiler does. }
(*$INCLUDE:'testio.inc'*)
PROGRAM retype_widths(input, output);
USES testio;

VAR
  i: INTEGER;
  w: INTEGER32;
  c: CINT;
  big: INTEGER64;

BEGIN
  w := 70000;
  i := RETYPE(INTEGER, w);
  WriteLabel('RETYPE(INTEGER, 70000)');
  WriteInt(i);
  WRITELN;
  i := -1;
  w := RETYPE(INTEGER32, i);
  WriteLabel('RETYPE(INTEGER32, -1 as INTEGER)');
  WriteInt(w);
  WRITELN;
  big := 4294967297;
  c := RETYPE(CINT, big);
  WriteLabel('RETYPE(CINT, 2^32 + 1)');
  WriteInt(c);
  WRITELN;
  c := -2;
  big := RETYPE(INTEGER64, c);
  WriteLabel('RETYPE(INTEGER64, -2 as CINT)');
  WriteInt(big);
  WRITELN;
  w := RETYPE(INTEGER32, c);
  WriteLabel('RETYPE(INTEGER32, -2 as CINT)');
  WriteInt(w);
  WRITELN;
END.
