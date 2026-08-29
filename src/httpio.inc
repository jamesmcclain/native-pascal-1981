{ INTERFACE header for httpio, HTTP/1.0 message handling.

  Scope: parsing a request and writing a response. This unit deals in HTTP
  mechanism only and holds no policy -- it reports what a message says and
  what is wrong with it, and leaves the choice of status code to the caller.
  That separation matters because the completion proxy's mapping is not the
  obvious one (a zero-length body is 413 there, not 400, because the size gate
  runs before any parsing), and burying that in a general HTTP unit would make
  the unit wrong for anything else.

  Parsing works on a ByteBuf holding whatever has been received so far, using
  INTEGER32 indices rather than pointer cursors: this dialect compares
  pointers only with = and <>, so a C-style `while (p < end)` walk does not
  compile, and offsets are the only workable form. Lengths are INTEGER32
  because a request body routinely exceeds a bare INTEGER's 32767.

  The raw buffer stays with the caller. HttpReq records where the header block
  ends, so the body is simply the bytes of that same buffer from head_len
  onward -- no copy, and no nested buffer inside the record.

  Requires bytebuf and netsock. }

INTERFACE;
UNIT httpio (HttpReqInit, HttpParseHead, HttpHeaderValue, HttpContentLength,
             HttpReadHead, HttpReadBody, HttpBodyLen,
             HttpWriteResponse, HttpReason,
             HttpAppendCRLF, HttpAppendStatusLine);

USES bytebuf, netsock;

CONST
  { Content-Length outcomes that are not lengths. Absent and malformed are
    distinct because they mean different things to a caller: a missing header
    is a message that simply carried no body, while an unparseable one is a
    client error. }
  HTTP_CL_ABSENT    = -1;
  HTTP_CL_MALFORMED = -2;

  { HttpReadHead outcomes. }
  HTTP_HEAD_OK        =  0;
  HTTP_HEAD_EOF       = -1;   { peer closed before the headers were complete }
  HTTP_HEAD_TIMEOUT   = -2;
  HTTP_HEAD_ERROR     = -3;
  HTTP_HEAD_TOO_LARGE = -4;   { header block exceeded the caller's ceiling }

TYPE
  HttpReq = RECORD
    method:         ByteStr;
    path:           ByteStr;
    version:        ByteStr;
    content_length: INTEGER32;  { or HTTP_CL_ABSENT / HTTP_CL_MALFORMED }
    head_len:       INTEGER32;  { bytes of header block, terminator included;
                                  the body begins here in the raw buffer }
    malformed:      BOOLEAN;    { the request line itself did not parse }
  END;

PROCEDURE HttpReqInit(VAR r: HttpReq);

{ Parse the header block already present in `raw`. Returns FALSE when the
  terminating blank line has not arrived yet, which is not an error -- the
  caller reads more and tries again. Accepts both CRLF and bare LF line
  endings: the standard requires CRLF, but a request typed by hand or sent by
  a minimal client often uses LF, and rejecting those makes debugging by
  telnet or netcat needlessly confusing. }
FUNCTION HttpParseHead(VAR raw: ByteBuf; VAR r: HttpReq): BOOLEAN;

{ Look up a header by name, case-insensitively as HTTP requires. Returns FALSE
  when absent. The value is trimmed of surrounding spaces and truncated at 255
  characters, which is ample for the headers anything here inspects. }
FUNCTION HttpHeaderValue(VAR raw: ByteBuf; VAR r: HttpReq; name: ByteStr;
                         VAR out: ByteStr): BOOLEAN;

{ The parsed Content-Length, or one of the HTTP_CL_ constants. }
FUNCTION HttpContentLength(VAR raw: ByteBuf; VAR r: HttpReq): INTEGER32;

{ Read from `fd` until the header block is complete, appending everything to
  `raw` -- which will usually also contain the first part of the body, since a
  read does not stop politely at the blank line. Returns one of the
  HTTP_HEAD_ constants. }
FUNCTION HttpReadHead(fd: INTEGER32; VAR raw: ByteBuf; VAR r: HttpReq;
                      max_head: INTEGER32; timeout_ms: INTEGER32): INTEGER32;

{ Bytes of body already present in `raw`. }
FUNCTION HttpBodyLen(VAR raw: ByteBuf; VAR r: HttpReq): INTEGER32;

{ Read until the body holds `want` bytes. Returns FALSE if the peer closed
  first, which is how a truncated request is detected -- the caller promised
  more in Content-Length than it sent. }
FUNCTION HttpReadBody(fd: INTEGER32; VAR raw: ByteBuf; VAR r: HttpReq;
                      want: INTEGER32; timeout_ms: INTEGER32): BOOLEAN;

{ Write a complete response: status line, Content-Type, Content-Length,
  Connection: close, blank line, body. Built in one buffer and sent in one
  call. Returns FALSE if the write failed, which for a server usually means
  the client hung up and is worth noticing but not worth panicking about. }
FUNCTION HttpWriteResponse(fd: INTEGER32; status: INTEGER32;
                           content_type: ByteStr;
                           VAR body: ByteBuf): BOOLEAN;

{ The reason phrase for a status code. Only the codes this toolchain actually
  emits are listed; anything else reports "Unknown", since inventing a phrase
  for an arbitrary number would be guessing. }
PROCEDURE HttpReason(status: INTEGER32; VAR out: ByteStr);

{ Building blocks, exported because a caller assembling a request by hand
  needs them and a CRLF cannot be written as a string literal in this
  dialect. }
PROCEDURE HttpAppendCRLF(VAR b: ByteBuf);
PROCEDURE HttpAppendStatusLine(VAR b: ByteBuf; status: INTEGER32);

END;
