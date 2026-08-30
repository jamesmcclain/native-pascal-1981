(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'proxycore.inc'*)
PROGRAM proxycore_unit(input, output);
{ The two proxycore entry points that deal in raw bytes, and so cannot be
  reached by the differential harness in tests/proxy/: a corpus that travels
  as JSON can only carry text that is already valid UTF-8, which is precisely
  what PxUtf8Valid exists to decide.

  Every other transform is checked against the Python implementation it
  replaces by tests/proxy/transforms_check.py, which is a far better test
  than anything hand-written here would be. }
USES bytebuf, jsonx, proxycore;

VAR
  b: ByteBuf;

PROCEDURE Check(name: ByteStr; VAR bytes: ByteBuf);
BEGIN
  WRITELN(name, ': valid=', PxUtf8Valid(bytes), ' chars=', PxCharLen(bytes),
          ' bytes=', BufLen(bytes));
END;

PROCEDURE Bytes(VAR out: ByteBuf; a, b, c, d: INTEGER32);
BEGIN
  BufClear(out);
  IF a >= 0 THEN BufAppendChar(out, CHR(a));
  IF b >= 0 THEN BufAppendChar(out, CHR(b));
  IF c >= 0 THEN BufAppendChar(out, CHR(c));
  IF d >= 0 THEN BufAppendChar(out, CHR(d));
END;

BEGIN
  BufInit(b, 0);

  BufAppendStr(b, 'plain ascii');
  Check('ascii', b);

  BufClear(b);
  Check('empty', b);

  { U+00E9, two bytes. }
  Bytes(b, 104, 195, 169, -1);
  Check('two-byte', b);

  { U+1F642, four bytes. }
  Bytes(b, 240, 159, 153, 130);
  Check('four-byte', b);

  { A continuation byte with no lead byte in front of it. }
  Bytes(b, 128, -1, -1, -1);
  Check('lone-continuation', b);

  { A lead byte whose continuation never arrives. }
  Bytes(b, 195, -1, -1, -1);
  Check('truncated', b);

  { C0 80: an overlong encoding of NUL. Length-only checking accepts this;
    a real decoder does not, which is why the second byte's legal range is
    narrowed per lead byte rather than being 80..BF throughout. }
  Bytes(b, 192, 128, -1, -1);
  Check('overlong-two', b);

  { E0 80 80: overlong three-byte form. }
  Bytes(b, 224, 128, 128, -1);
  Check('overlong-three', b);

  { ED A0 80: a UTF-16 surrogate half, which is not a character. }
  Bytes(b, 237, 160, 128, -1);
  Check('surrogate', b);

  { F4 90 80 80: U+110000, one past the last code point. }
  Bytes(b, 244, 144, 128, 128);
  Check('above-max', b);

  { F5 ...: no lead byte above F4 is legal at all. }
  Bytes(b, 245, 128, 128, 128);
  Check('bad-lead', b);

  { The smallest legal two-byte form, U+0080. }
  Bytes(b, 194, 128, -1, -1);
  Check('min-two-byte', b);

  BufFree(b);
END.
