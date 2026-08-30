{ DIALECT: extended }
(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'httpio.inc'*)
PROGRAM httpio_parse(input, output);
{ Request parsing, exercised directly on buffers rather than over a socket, so
  every case is deterministic and a failure points at the parser rather than
  at timing. The socket path gets its own fixture.

  A CRLF cannot be written as a string literal in this dialect, so requests
  are assembled with HttpAppendCRLF. }
USES bytebuf, netsock, httpio;

VAR
  raw: ByteBuf;
  req: HttpReq;
  v: ByteStr;

PROCEDURE StartRequest(line: ByteStr);
BEGIN
  BufClear(raw);
  HttpReqInit(req);
  BufAppendStr(raw, line);
  HttpAppendCRLF(raw);
END;

PROCEDURE AddHeader(h: ByteStr);
BEGIN
  BufAppendStr(raw, h);
  HttpAppendCRLF(raw);
END;

PROCEDURE EndHeaders;
BEGIN
  HttpAppendCRLF(raw);
END;

PROCEDURE Report(tag: ByteStr);
BEGIN
  WRITE(tag, ': parsed=', HttpParseHead(raw, req));
  WRITE(' method=', req.method, ' path=', req.path);
  WRITELN(' cl=', req.content_length, ' malformed=', req.malformed);
END;

BEGIN
  BufInit(raw, 0);

  { A well-formed POST with a body. }
  StartRequest('POST /complete HTTP/1.1');
  AddHeader('Host: 127.0.0.1');
  AddHeader('Content-Type: application/json');
  AddHeader('Content-Length: 17');
  EndHeaders;
  BufAppendStr(raw, '{"goal":"finish"}');
  Report('post');
  WRITELN('  body-present=', HttpBodyLen(raw, req));

  { Header lookup is case-insensitive, and the value is trimmed. }
  WRITELN('  ctype-found=', HttpHeaderValue(raw, req, 'CONTENT-TYPE', v));
  WRITELN('  ctype=[', v, ']');
  WRITELN('  absent=', HttpHeaderValue(raw, req, 'x-nope', v));

  { A GET with no body at all. }
  StartRequest('GET /health HTTP/1.1');
  AddHeader('Host: x');
  EndHeaders;
  Report('get');

  { Content-Length that is not a number. The parser reports malformed rather
    than guessing a length; choosing a status code is the caller's job. }
  StartRequest('POST /complete HTTP/1.1');
  AddHeader('Content-Length: abc');
  EndHeaders;
  Report('bad-length');

  { An empty Content-Length value is malformed too, not zero. }
  StartRequest('POST /complete HTTP/1.1');
  AddHeader('Content-Length:');
  EndHeaders;
  Report('empty-length');

  { A length that would overflow INTEGER32 is refused rather than wrapping
    into a negative number, which would read as an ordinary small body. }
  StartRequest('POST /complete HTTP/1.1');
  AddHeader('Content-Length: 99999999999');
  EndHeaders;
  Report('huge-length');

  { Bare LF line endings, as a hand-typed or minimal-client request sends. }
  BufClear(raw);
  HttpReqInit(req);
  BufAppendStr(raw, 'GET /health HTTP/1.0');
  BufAppendChar(raw, CHR(10));
  BufAppendStr(raw, 'Content-Length: 4');
  BufAppendChar(raw, CHR(10));
  BufAppendChar(raw, CHR(10));
  BufAppendStr(raw, 'abcd');
  Report('bare-lf');
  WRITELN('  body-present=', HttpBodyLen(raw, req));

  { An incomplete header block is not an error: the caller reads more. }
  BufClear(raw);
  HttpReqInit(req);
  BufAppendStr(raw, 'GET /health HTTP/1.1');
  HttpAppendCRLF(raw);
  WRITELN('incomplete: parsed=', HttpParseHead(raw, req));

  { A request line with only one field cannot be honoured. }
  StartRequest('GARBAGE');
  EndHeaders;
  Report('malformed-line');

  { Extra spaces between fields are tolerated. }
  StartRequest('GET    /spaced    HTTP/1.1');
  EndHeaders;
  Report('extra-spaces');

  { Reason phrases for the codes the proxy emits. }
  HttpReason(200, v); WRITE('reasons: 200=', v);
  HttpReason(400, v); WRITE(' 400=', v);
  HttpReason(413, v); WRITE(' 413=', v);
  HttpReason(502, v); WRITE(' 502=', v);
  HttpReason(599, v); WRITELN(' 599=', v);

  BufFree(raw);
END.
