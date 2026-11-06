{ DIALECT: extended }
{ NEW-6: an integer literal argument of an intrinsic is not forced to the
  type of the assignment it appears in. HIBYTE(258) assigned to an
  INTEGER32 was rejected (its 258 had become an INTEGER32, which HIBYTE
  does not take), and ABS(-5) into a WORD8 rejected -5 as a WORD8. The
  context still reaches an argument that fits it, so SQR(1000) into an
  INTEGER32 is checked at 32 bits. HIBYTE and LOBYTE return an INTEGER
  or WORD, which narrows into an 8-bit target only as a constant the
  typechecker folds, so they are not assigned to one here. }
PROGRAM ExtendedIntrinsicLiteralContext(OUTPUT);
VAR
  x: INTEGER32;
  q: INTEGER64;
  w: WORD;
  i: INTEGER;
  b: INTEGER8;
  w8: WORD8;
  c: CHAR;
BEGIN
  x := HIBYTE(258);
  WRITELN(x);
  x := LOBYTE(258);
  WRITELN(x);
  q := HIBYTE(40000);
  WRITELN(q);
  w := HIBYTE(258);
  WRITELN(w);
  i := LOBYTE(-1);
  WRITELN(i);
  x := BYWORD(1, 2);
  WRITELN(x);
  b := BYWORD(0, 127);
  WRITELN(b);
  x := ORD(5);
  WRITELN(x);
  x := SUCC(5);
  WRITELN(x);
  w := SUCC(-1);
  WRITELN(w);
  w8 := ABS(-5);
  WRITELN(w8);
  w := ABS(-5);
  WRITELN(w);
  x := SQR(1000);
  WRITELN(x);
  x := ABS(-70000);
  WRITELN(x);
  b := ORD(CHR(65));
  WRITELN(b);
  c := CHR(LOBYTE(16706));
  WRITELN(c)
END.
