{ LSTRING value semantics and the length byte at element 0. }
(*$INCLUDE:'testio.inc'*)
PROGRAM lstring_value(input, output);
USES testio;

VAR
  a, b: Str255;
  c: LSTRING(10);

PROCEDURE Clobber(s: Str255);
BEGIN
  s[1] := 'X';
  s[0] := CHR(1);
  WriteLabel('callee');
  WriteStr(s);
  WRITELN;
END;

BEGIN
  a := 'hello';
  b := a;
  b[1] := 'j';
  WriteLabel('a =');
  WriteStr(a);
  WRITELN;
  WriteLabel('b =');
  WriteStr(b);
  WRITELN;
  Clobber(a);
  WriteLabel('a after call');
  WriteStr(a);
  WRITELN;
  WriteLabel('length');
  WriteInt(ORD(a[0]));
  WRITELN;
  a[0] := CHR(3);
  WriteLabel('truncated');
  WriteStr(a);
  WRITELN;
  a := '';
  WriteLabel('empty length');
  WriteInt(ORD(a[0]));
  WRITELN;
  c := 'short';
  WriteLabel('LSTRING(10) length');
  WriteInt(ORD(c[0]));
  WRITELN;
  WriteLabel('compare');
  WriteBool(b = 'jello');
  WRITE(' ');
  WriteBool(a < 'az');
  WRITE(' ');
  WriteBool('abc' < 'abd');
  WRITE(' ');
  WriteBool(b <> 'jell');
  WRITELN;
END.
