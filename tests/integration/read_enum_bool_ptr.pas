PROGRAM rbp(output);
{ READ/READLN destinations of the manual's extended READFN types
  (13610-13623), both from stdin and from a TEXT file: an enumerated
  variable read as a numeric ordinal, BOOLEANs read by identifier name
  (case-insensitively) and by number alike, and a pointer read as the
  same unsigned-decimal number WRITE prints for it -- the round trip the
  manual's implementation-defined pointer format requires. }
TYPE
  hue = (red, green, blue);
VAR
  f: TEXT;
  c: hue;
  a, b: BOOLEAN;
  p: ^INTEGER;
BEGIN
  READLN(c, a, b, p);
  WRITELN(ORD(c), ' ', a, ' ', b, ' ', p);
  ASSIGN(f, '/tmp/native_pascal_test_read_enum_bool_ptr.txt');
  REWRITE(f);
  WRITELN(f, '1 false 65536');
  CLOSE(f);
  RESET(f);
  READLN(f, c, a, p);
  CLOSE(f);
  WRITELN(ORD(c), ' ', a, ' ', p);
END.
