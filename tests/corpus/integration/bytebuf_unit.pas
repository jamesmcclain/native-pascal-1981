{ DIALECT: extended }
(*$INCLUDE:'bytebuf.inc'*)
PROGRAM bytebuf_unit(input, output);
{ Exercises the bytebuf unit, including the case the dialect makes easy to get
  wrong: growth past the 16-bit boundary, where a capacity held in a bare
  INTEGER would silently wrap and the buffer would corrupt memory. }
USES bytebuf;

VAR
  b, other: ByteBuf;
  s: ByteStr;
  i, n, m, mismatches: INTEGER32;

BEGIN
  { --- appending and access --- }
  BufInit(b, 0);
  BufAppendStr(b, 'HTTP/1.0 200 OK');
  WRITELN('len=', BufLen(b));
  BufSliceToStr(b, 0, 8, s);
  WRITELN('slice=', s);
  WRITELN('at0=', BufAt(b, 0), ' at8=', BufAt(b, 8));
  WRITELN('oob=', ORD(BufAt(b, 9999)));

  { --- searching --- }
  WRITELN('idx_space=', BufIndexOfChar(b, ' ', 0));
  WRITELN('idx_200=', BufIndexOfStr(b, '200', 0));
  WRITELN('idx_missing=', BufIndexOfStr(b, 'zzz', 0));
  WRITELN('match=', BufMatchesStrAt(b, 9, '200'));
  WRITELN('ci=', BufMatchesStrAtCI(b, 0, 'http/1.0'));
  WRITELN('ci_neg=', BufMatchesStrAt(b, 0, 'http/1.0'));

  { --- integers --- }
  BufClear(b);
  BufAppendInt(b, 0);
  BufAppendChar(b, ' ');
  BufAppendInt(b, 8790);
  BufAppendChar(b, ' ');
  BufAppendInt(b, -1234);
  BufAppendChar(b, ' ');
  n := 100000;
  BufAppendInt(b, n);
  BufSliceToStr(b, 0, BufLen(b), s);
  WRITELN('ints=', s);

  { The ends of the INTEGER32 range. The absolute value of the minimum is not
    representable in INTEGER32, so a formatter that takes the magnitude in the
    argument's own width negates it into another negative number, never enters
    its digit loop, and emits a bare "-". The minimum is checked both through a
    variable and as a literal so the constant folder and codegen cannot cover up
    for each other. }
  BufClear(b);
  n := -2147483647 - 1;
  m := 2147483647;
  BufAppendInt(b, n);
  BufAppendChar(b, ' ');
  BufAppendInt(b, m);
  BufAppendChar(b, ' ');
  BufAppendInt(b, -2147483648);
  BufAppendChar(b, ' ');
  BufAppendInt(b, -1);
  BufAppendChar(b, ' ');
  BufAppendInt(b, -100);
  BufAppendChar(b, ' ');
  BufAppendInt(b, 1000000000);
  BufSliceToStr(b, 0, BufLen(b), s);
  WRITELN('edges=', s);

  { --- equality and appending one buffer to another --- }
  BufClear(b);
  BufAppendStr(b, 'abc');
  WRITELN('eq=', BufEqualsStr(b, 'abc'), ' neq=', BufEqualsStr(b, 'abcd'));
  BufInit(other, 0);
  BufAppendStr(other, 'def');
  BufAppendBuf(b, other);
  BufSliceToStr(b, 0, BufLen(b), s);
  WRITELN('joined=', s);

  { --- C string round trip --- }
  BufClear(b);
  BufAppendStr(b, 'cstr');
  BufClear(other);
  BufAppendCStr(other, BufCStr(b));
  WRITELN('roundtrip=', BufEqualsStr(other, 'cstr'));

  { --- growth past the 16-bit boundary --- }
  BufClear(b);
  n := 100000;
  i := 0;
  WHILE i < n DO
  BEGIN
    BufAppendChar(b, CHR(65 + RETYPE(INTEGER, i MOD 26)));
    i := i + 1;
  END;
  WRITELN('biglen=', BufLen(b));
  mismatches := 0;
  i := 0;
  WHILE i < n DO
  BEGIN
    IF BufAt(b, i) <> CHR(65 + RETYPE(INTEGER, i MOD 26)) THEN
      mismatches := mismatches + 1;
    i := i + 1;
  END;
  WRITELN('mismatches=', mismatches);

  { a search that has to run the whole length }
  BufTruncate(b, 10);
  WRITELN('trunc=', BufLen(b));

  { --- the growth policy, near the 2147483647-byte limit, without
    allocating: doubling from 1 GiB or more is capped instead of wrapping
    to a negative capacity (bytebuf_overflow.pas covers the requests that
    cannot be met at all). --- }
  WRITELN('grow_none=', BufGrowCap(512, 300));
  WRITELN('grow_min=', BufGrowCap(0, 1));
  WRITELN('grow_double=', BufGrowCap(256, 257));
  WRITELN('grow_loop=', BufGrowCap(256, 100000));
  WRITELN('grow_1g=', BufGrowCap(1073741824, 1073741825));
  WRITELN('grow_top=', BufGrowCap(1610612736, 2147483647));
  WRITELN('grow_from_min=', BufGrowCap(256, 2147483647));
  WRITELN('grow_at_cap=', BufGrowCap(2147483647, 2147483647));

  BufFree(b);
  BufFree(other);
  WRITELN('done');
END.
