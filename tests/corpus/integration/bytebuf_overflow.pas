{ DIALECT: extended }
(*$INCLUDE:'bytebuf.inc'*)
PROGRAM bytebuf_overflow(input, output);
{ An append that would take a ByteBuf past 2147483647 bytes stops with a
  bytebuf run-time error before it allocates or copies anything. The length
  is set near the limit by hand, so nothing near 2 GiB is ever allocated:
  the request is refused on its size alone. b.len + 100 in INTEGER32 used to
  wrap (or trip MATHCK inside the unit) instead. }
USES bytebuf;

VAR
  b: ByteBuf;
  s: ByteStr;

BEGIN
  BufInit(b, 0);
  BufAppendStr(b, 'ok');
  WRITELN('len=', BufLen(b));
  s := 'payload';
  b.len := 2147483600;
  b.cap := 2147483647;
  WRITELN('appending');
  BufAppendBytes(b, ADR s, 100);
  WRITELN('not reached');
END.
