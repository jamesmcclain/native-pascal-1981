{ CONCAT appends an LSTRING or a string literal to a local, itself included. }
(*$INCLUDE:'testio.inc'*)
PROGRAM concat(input, output);
USES testio;

VAR
  s, t: Str255;

BEGIN
  s := 'abc';
  t := 'de';
  CONCAT(s, t);
  CONCAT(s, 'fgh');
  t := '!!';
  CONCAT(s, t);
  CONCAT(s, s);
  WriteLabel('result');
  WriteStr(s);
  WRITELN;
  WriteLabel('length');
  WriteInt(ORD(s[0]));
  WRITELN;
END.
