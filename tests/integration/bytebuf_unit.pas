(*$INCLUDE:'bytebuf.inc'*)
PROGRAM bytebuf_unit(input, output);
{ Exercises the bytebuf unit, including the case the dialect makes easy to get
  wrong: growth past the 16-bit boundary, where a capacity held in a bare
  INTEGER would silently wrap and the buffer would corrupt memory. }
USES bytebuf;

VAR
  b, other: ByteBuf;
  s: ByteStr;
  i, n, mismatches: INTEGER32;

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

  BufFree(b);
  BufFree(other);
  WRITELN('done');
END.
