{ IMPLEMENTATION of httpio. See httpio.inc for the contract and for why this
  unit carries no status-code policy. }

(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'httpio.inc'*)

IMPLEMENTATION OF httpio;

CONST
  HTTP_CR = 13;
  HTTP_LF = 10;
  HTTP_SPACE = 32;
  HTTP_TAB = 9;

PROCEDURE HttpReqInit(VAR r: HttpReq);
BEGIN
  r.method := '';
  r.path := '';
  r.version := '';
  r.content_length := HTTP_CL_ABSENT;
  r.head_len := 0;
  r.malformed := FALSE;
END;

PROCEDURE HttpAppendCRLF(VAR b: ByteBuf);
BEGIN
  BufAppendChar(b, CHR(HTTP_CR));
  BufAppendChar(b, CHR(HTTP_LF));
END;

{ ------------------------------------------------------------------ }
{ Locating the end of the header block                                }
{ ------------------------------------------------------------------ }

{ Index just past the blank line ending the headers, or -1 if it has not
  arrived. Scanned by hand rather than searched for as a literal, because a
  CRLFCRLF cannot be written as a string constant here. Both CRLFCRLF and the
  bare LFLF a hand-typed request produces are recognised. }
FUNCTION HttpHeadEnd(VAR raw: ByteBuf): INTEGER32;
VAR
  i, n, found: INTEGER32;
BEGIN
  n := BufLen(raw);
  found := -1;
  i := 0;
  WHILE (i < n) AND (found < 0) DO
  BEGIN
    IF ORD(BufAt(raw, i)) = HTTP_LF THEN
    BEGIN
      IF (i + 1 < n) AND (ORD(BufAt(raw, i + 1)) = HTTP_LF) THEN
        found := i + 2
      ELSE IF (i + 2 < n) AND (ORD(BufAt(raw, i + 1)) = HTTP_CR)
              AND (ORD(BufAt(raw, i + 2)) = HTTP_LF) THEN
        found := i + 3;
    END;
    i := i + 1;
  END;
  HttpHeadEnd := found;
END;

{ End of the line starting at `from`, not counting its terminator. }
FUNCTION HttpLineEnd(VAR raw: ByteBuf; from: INTEGER32;
                     limit: INTEGER32): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := from;
  WHILE (i < limit) AND (ORD(BufAt(raw, i)) <> HTTP_LF) DO
    i := i + 1;
  IF (i > from) AND (ORD(BufAt(raw, i - 1)) = HTTP_CR) THEN
    HttpLineEnd := i - 1
  ELSE
    HttpLineEnd := i;
END;

{ Start of the next line after the one ending at `line_end`. }
FUNCTION HttpNextLine(VAR raw: ByteBuf; line_end: INTEGER32;
                      limit: INTEGER32): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := line_end;
  WHILE (i < limit) AND (ORD(BufAt(raw, i)) <> HTTP_LF) DO
    i := i + 1;
  HttpNextLine := i + 1;
END;

{ ------------------------------------------------------------------ }
{ Headers                                                             }
{ ------------------------------------------------------------------ }

{ Header lookup takes a head_len rather than a record, so that one
  implementation serves requests and responses alike: the two differ only in
  what their first line means, and this skips that line either way. }
FUNCTION HttpFindHeader(VAR raw: ByteBuf; head_len: INTEGER32; name: ByteStr;
                        VAR out: ByteStr): BOOLEAN;
VAR
  pos, line_end, colon, value_start, value_end, name_len: INTEGER32;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  name_len := ORD(name[0]);
  { Start after the request or status line. }
  line_end := HttpLineEnd(raw, 0, head_len);
  pos := HttpNextLine(raw, line_end, head_len);
  WHILE (pos < head_len) AND (NOT found) DO
  BEGIN
    line_end := HttpLineEnd(raw, pos, head_len);
    IF line_end > pos THEN
    BEGIN
      IF BufMatchesStrAtCI(raw, pos, name) THEN
      BEGIN
        colon := pos + name_len;
        IF (colon < line_end) AND (BufAt(raw, colon) = ':') THEN
        BEGIN
          value_start := colon + 1;
          WHILE (value_start < line_end) AND
                ((ORD(BufAt(raw, value_start)) = HTTP_SPACE) OR
                 (ORD(BufAt(raw, value_start)) = HTTP_TAB)) DO
            value_start := value_start + 1;
          value_end := line_end;
          WHILE (value_end > value_start) AND
                ((ORD(BufAt(raw, value_end - 1)) = HTTP_SPACE) OR
                 (ORD(BufAt(raw, value_end - 1)) = HTTP_TAB)) DO
            value_end := value_end - 1;
          BufSliceToStr(raw, value_start, value_end - value_start, out);
          found := TRUE;
        END;
      END;
    END;
    pos := HttpNextLine(raw, line_end, head_len);
  END;
  IF NOT found THEN out := '';
  HttpFindHeader := found;
END;

FUNCTION HttpHeaderValue(VAR raw: ByteBuf; VAR r: HttpReq; name: ByteStr;
                         VAR out: ByteStr): BOOLEAN;
BEGIN
  HttpHeaderValue := HttpFindHeader(raw, r.head_len, name, out);
END;

FUNCTION HttpParseCL(VAR raw: ByteBuf; head_len: INTEGER32): INTEGER32;
VAR
  header_value: ByteStr;
  i, n, digit, total, ceiling: INTEGER32;
  bad: BOOLEAN;
BEGIN
  IF NOT HttpFindHeader(raw, head_len, 'content-length', header_value) THEN
    HttpParseCL := HTTP_CL_ABSENT
  ELSE
  BEGIN
    n := ORD(header_value[0]);
    IF n = 0 THEN
      HttpParseCL := HTTP_CL_MALFORMED
    ELSE
    BEGIN
      bad := FALSE;
      total := 0;
      ceiling := 200000000;
      i := 1;
      WHILE (i <= n) AND (NOT bad) DO
      BEGIN
        digit := ORD(header_value[i]) - 48;
        IF (digit < 0) OR (digit > 9) THEN
          bad := TRUE
        ELSE
        BEGIN
          { Refuse anything that would overflow INTEGER32 rather than
            wrapping into a negative length, which would then read as a
            perfectly ordinary "too small" value further up. }
          IF total > ceiling THEN
            bad := TRUE
          ELSE
            total := total * 10 + digit;
        END;
        i := i + 1;
      END;
      IF bad THEN
        HttpParseCL := HTTP_CL_MALFORMED
      ELSE
        HttpParseCL := total;
    END;
  END;
END;

FUNCTION HttpContentLength(VAR raw: ByteBuf; VAR r: HttpReq): INTEGER32;
BEGIN
  HttpContentLength := HttpParseCL(raw, r.head_len);
END;

{ ------------------------------------------------------------------ }
{ Request line                                                        }
{ ------------------------------------------------------------------ }

PROCEDURE HttpParseRequestLine(VAR raw: ByteBuf; VAR r: HttpReq;
                               line_end: INTEGER32);
VAR
  i, start, field: INTEGER32;
BEGIN
  field := 0;
  i := 0;
  WHILE (i <= line_end) AND (field < 3) DO
  BEGIN
    { Skip any run of spaces between fields. }
    WHILE (i < line_end) AND (ORD(BufAt(raw, i)) = HTTP_SPACE) DO
      i := i + 1;
    start := i;
    WHILE (i < line_end) AND (ORD(BufAt(raw, i)) <> HTTP_SPACE) DO
      i := i + 1;
    IF i > start THEN
    BEGIN
      IF field = 0 THEN BufSliceToStr(raw, start, i - start, r.method)
      ELSE IF field = 1 THEN BufSliceToStr(raw, start, i - start, r.path)
      ELSE BufSliceToStr(raw, start, i - start, r.version);
      field := field + 1;
    END
    ELSE
      i := line_end + 1;      { nothing left to take }
  END;
  { A request line needs at least a method and a target. The version is
    optional here: HTTP/0.9-style "GET /path" is ancient but harmless to
    accept, and rejecting it would gain nothing. }
  IF field < 2 THEN r.malformed := TRUE;
END;

FUNCTION HttpParseHead(VAR raw: ByteBuf; VAR r: HttpReq): BOOLEAN;
VAR
  head_end, line_end: INTEGER32;
BEGIN
  head_end := HttpHeadEnd(raw);
  IF head_end < 0 THEN
    HttpParseHead := FALSE
  ELSE
  BEGIN
    r.head_len := head_end;
    line_end := HttpLineEnd(raw, 0, head_end);
    HttpParseRequestLine(raw, r, line_end);
    r.content_length := HttpParseCL(raw, head_end);
    HttpParseHead := TRUE;
  END;
END;

{ ------------------------------------------------------------------ }
{ Reading                                                             }
{ ------------------------------------------------------------------ }

FUNCTION HttpReadHead(fd: INTEGER32; VAR raw: ByteBuf; VAR r: HttpReq;
                      max_head: INTEGER32; timeout_ms: INTEGER32): INTEGER32;
VAR
  got, outcome: INTEGER32;
  complete, stop: BOOLEAN;
BEGIN
  outcome := HTTP_HEAD_OK;
  stop := FALSE;
  complete := HttpParseHead(raw, r);
  WHILE (NOT complete) AND (NOT stop) DO
  BEGIN
    got := NetRead(fd, raw, timeout_ms);
    IF got = 0 THEN
    BEGIN
      outcome := HTTP_HEAD_EOF;
      stop := TRUE;
    END
    ELSE IF got = NET_TIMEOUT THEN
    BEGIN
      outcome := HTTP_HEAD_TIMEOUT;
      stop := TRUE;
    END
    ELSE IF got < 0 THEN
    BEGIN
      outcome := HTTP_HEAD_ERROR;
      stop := TRUE;
    END
    ELSE IF (max_head > 0) AND (BufLen(raw) > max_head) AND
            (HttpHeadEnd(raw) < 0) THEN
    BEGIN
      outcome := HTTP_HEAD_TOO_LARGE;
      stop := TRUE;
    END
    ELSE
      complete := HttpParseHead(raw, r);
  END;
  HttpReadHead := outcome;
END;

FUNCTION HttpBodyLen(VAR raw: ByteBuf; VAR r: HttpReq): INTEGER32;
BEGIN
  HttpBodyLen := BufLen(raw) - r.head_len;
END;

FUNCTION HttpReadBody(fd: INTEGER32; VAR raw: ByteBuf; VAR r: HttpReq;
                      want: INTEGER32; timeout_ms: INTEGER32): BOOLEAN;
VAR
  got: INTEGER32;
  ok, stop: BOOLEAN;
BEGIN
  ok := TRUE;
  stop := FALSE;
  WHILE (HttpBodyLen(raw, r) < want) AND (NOT stop) DO
  BEGIN
    got := NetRead(fd, raw, timeout_ms);
    IF got <= 0 THEN
    BEGIN
      { End of stream, a timeout, or an error all mean the same thing to the
        caller: the promised bytes are not coming. }
      ok := FALSE;
      stop := TRUE;
    END;
  END;
  HttpReadBody := ok;
END;

{ ------------------------------------------------------------------ }
{ Responses                                                           }
{ ------------------------------------------------------------------ }

PROCEDURE HttpReason(status: INTEGER32; VAR out: ByteStr);
BEGIN
  IF status = 200 THEN out := 'OK'
  ELSE IF status = 400 THEN out := 'Bad Request'
  ELSE IF status = 404 THEN out := 'Not Found'
  ELSE IF status = 405 THEN out := 'Method Not Allowed'
  ELSE IF status = 413 THEN out := 'Payload Too Large'
  ELSE IF status = 500 THEN out := 'Internal Server Error'
  ELSE IF status = 501 THEN out := 'Not Implemented'
  ELSE IF status = 502 THEN out := 'Bad Gateway'
  ELSE IF status = 503 THEN out := 'Service Unavailable'
  ELSE out := 'Unknown';
END;

PROCEDURE HttpAppendStatusLine(VAR b: ByteBuf; status: INTEGER32);
VAR
  reason: ByteStr;
BEGIN
  { HTTP/1.0 with Connection: close, matching the reference implementation:
    one request per connection, response framed by Content-Length. }
  BufAppendStr(b, 'HTTP/1.0 ');
  BufAppendInt(b, status);
  BufAppendChar(b, ' ');
  HttpReason(status, reason);
  BufAppendStr(b, reason);
  HttpAppendCRLF(b);
END;

FUNCTION HttpWriteResponse(fd: INTEGER32; status: INTEGER32;
                           content_type: ByteStr;
                           VAR body: ByteBuf): BOOLEAN;
VAR
  out: ByteBuf;
  sent, total: INTEGER32;
BEGIN
  BufInit(out, 0);
  HttpAppendStatusLine(out, status);
  BufAppendStr(out, 'Content-Type: ');
  BufAppendStr(out, content_type);
  HttpAppendCRLF(out);
  BufAppendStr(out, 'Content-Length: ');
  BufAppendInt(out, BufLen(body));
  HttpAppendCRLF(out);
  BufAppendStr(out, 'Connection: close');
  HttpAppendCRLF(out);
  HttpAppendCRLF(out);
  BufAppendBuf(out, body);
  { Capture the length before freeing: BufFree zeroes it, so comparing
    afterwards would test sent = 0 and call every successful write a
    failure. }
  total := BufLen(out);
  sent := NetWrite(fd, out);
  BufFree(out);
  HttpWriteResponse := sent = total;
END;


{ ------------------------------------------------------------------ }
{ Client side: building requests                                      }
{ ------------------------------------------------------------------ }

PROCEDURE HttpAppendRequestLine(VAR b: ByteBuf; method: ByteStr;
                                path: ByteStr);
BEGIN
  BufAppendStr(b, method);
  BufAppendChar(b, ' ');
  BufAppendStr(b, path);
  BufAppendStr(b, ' HTTP/1.0');
  HttpAppendCRLF(b);
END;

PROCEDURE HttpAppendHeader(VAR b: ByteBuf; name: ByteStr; text: ByteStr);
BEGIN
  BufAppendStr(b, name);
  BufAppendStr(b, ': ');
  BufAppendStr(b, text);
  HttpAppendCRLF(b);
END;

PROCEDURE HttpAppendHeaderInt(VAR b: ByteBuf; name: ByteStr;
                              num: INTEGER32);
BEGIN
  BufAppendStr(b, name);
  BufAppendStr(b, ': ');
  BufAppendInt(b, num);
  HttpAppendCRLF(b);
END;

PROCEDURE HttpEndHeaders(VAR b: ByteBuf);
BEGIN
  HttpAppendCRLF(b);
END;

{ ------------------------------------------------------------------ }
{ Client side: reading responses                                      }
{ ------------------------------------------------------------------ }

PROCEDURE HttpRespInit(VAR r: HttpResp);
BEGIN
  r.version := '';
  r.status := 0;
  r.reason := '';
  r.content_length := HTTP_CL_ABSENT;
  r.head_len := 0;
  r.malformed := FALSE;
END;

PROCEDURE HttpParseStatusLine(VAR raw: ByteBuf; VAR r: HttpResp;
                              line_end: INTEGER32);
VAR
  i, j, start, n, digit, code: INTEGER32;
  tok: ByteStr;
  ok: BOOLEAN;
BEGIN
  i := 0;
  WHILE (i < line_end) AND (ORD(BufAt(raw, i)) = HTTP_SPACE) DO
    i := i + 1;
  start := i;
  WHILE (i < line_end) AND (ORD(BufAt(raw, i)) <> HTTP_SPACE) DO
    i := i + 1;
  IF i > start THEN
    BufSliceToStr(raw, start, i - start, r.version)
  ELSE
    r.malformed := TRUE;

  WHILE (i < line_end) AND (ORD(BufAt(raw, i)) = HTTP_SPACE) DO
    i := i + 1;
  start := i;
  WHILE (i < line_end) AND (ORD(BufAt(raw, i)) <> HTTP_SPACE) DO
    i := i + 1;
  IF i > start THEN
  BEGIN
    BufSliceToStr(raw, start, i - start, tok);
    n := ORD(tok[0]);
    { A status code is exactly three digits. Insisting on that is not
      pedantry: it is also what keeps the accumulation below from
      overflowing on a status line full of digits. }
    ok := n = 3;
    code := 0;
    j := 1;
    WHILE (j <= n) AND ok DO
    BEGIN
      digit := ORD(tok[j]) - 48;
      IF (digit < 0) OR (digit > 9) THEN
        ok := FALSE
      ELSE
        code := code * 10 + digit;
      j := j + 1;
    END;
    IF ok THEN r.status := code ELSE r.malformed := TRUE;
  END
  ELSE
    r.malformed := TRUE;

  { Whatever is left is the reason phrase, spaces and all. It may be absent
    entirely, which is legal and means nothing is wrong. }
  WHILE (i < line_end) AND (ORD(BufAt(raw, i)) = HTTP_SPACE) DO
    i := i + 1;
  IF i < line_end THEN
    BufSliceToStr(raw, i, line_end - i, r.reason)
  ELSE
    r.reason := '';
END;

FUNCTION HttpParseRespHead(VAR raw: ByteBuf; VAR r: HttpResp): BOOLEAN;
VAR
  head_end, line_end: INTEGER32;
BEGIN
  head_end := HttpHeadEnd(raw);
  IF head_end < 0 THEN
    HttpParseRespHead := FALSE
  ELSE
  BEGIN
    r.head_len := head_end;
    line_end := HttpLineEnd(raw, 0, head_end);
    HttpParseStatusLine(raw, r, line_end);
    r.content_length := HttpParseCL(raw, head_end);
    HttpParseRespHead := TRUE;
  END;
END;

FUNCTION HttpRespHeaderValue(VAR raw: ByteBuf; VAR r: HttpResp;
                             name: ByteStr; VAR out: ByteStr): BOOLEAN;
BEGIN
  HttpRespHeaderValue := HttpFindHeader(raw, r.head_len, name, out);
END;

FUNCTION HttpRespContentLength(VAR raw: ByteBuf; VAR r: HttpResp): INTEGER32;
BEGIN
  HttpRespContentLength := HttpParseCL(raw, r.head_len);
END;

{ The same read loop as HttpReadHead, written out again rather than shared.
  The only difference is which parse routine decides the headers are
  complete, and with no procedural types in this dialect there is no way to
  pass that in -- a shared version would have to take a flag and switch on it
  inside the loop, which is longer than the duplication it saves. }
FUNCTION HttpReadRespHead(fd: INTEGER32; VAR raw: ByteBuf; VAR r: HttpResp;
                          max_head: INTEGER32;
                          timeout_ms: INTEGER32): INTEGER32;
VAR
  got, outcome: INTEGER32;
  complete, stop: BOOLEAN;
BEGIN
  outcome := HTTP_HEAD_OK;
  stop := FALSE;
  complete := HttpParseRespHead(raw, r);
  WHILE (NOT complete) AND (NOT stop) DO
  BEGIN
    got := NetRead(fd, raw, timeout_ms);
    IF got = 0 THEN
    BEGIN
      outcome := HTTP_HEAD_EOF;
      stop := TRUE;
    END
    ELSE IF got = NET_TIMEOUT THEN
    BEGIN
      outcome := HTTP_HEAD_TIMEOUT;
      stop := TRUE;
    END
    ELSE IF got < 0 THEN
    BEGIN
      outcome := HTTP_HEAD_ERROR;
      stop := TRUE;
    END
    ELSE IF (max_head > 0) AND (BufLen(raw) > max_head) AND
            (HttpHeadEnd(raw) < 0) THEN
    BEGIN
      outcome := HTTP_HEAD_TOO_LARGE;
      stop := TRUE;
    END
    ELSE
      complete := HttpParseRespHead(raw, r);
  END;
  HttpReadRespHead := outcome;
END;

FUNCTION HttpRespBodyLen(VAR raw: ByteBuf; VAR r: HttpResp): INTEGER32;
BEGIN
  HttpRespBodyLen := BufLen(raw) - r.head_len;
END;

FUNCTION HttpReadRespBody(fd: INTEGER32; VAR raw: ByteBuf; VAR r: HttpResp;
                          want: INTEGER32; timeout_ms: INTEGER32): BOOLEAN;
VAR
  got: INTEGER32;
  ok, stop: BOOLEAN;
BEGIN
  ok := TRUE;
  stop := FALSE;
  WHILE (HttpRespBodyLen(raw, r) < want) AND (NOT stop) DO
  BEGIN
    got := NetRead(fd, raw, timeout_ms);
    IF got <= 0 THEN
    BEGIN
      ok := FALSE;
      stop := TRUE;
    END;
  END;
  HttpReadRespBody := ok;
END;

PROCEDURE HttpRespBodyToBuf(VAR raw: ByteBuf; VAR r: HttpResp;
                            VAR out: ByteBuf);
VAR
  base: ADRMEM;
  n: INTEGER32;
BEGIN
  n := HttpRespBodyLen(raw, r);
  IF n > 0 THEN
  BEGIN
    base := BufPtr(raw);
    BufAppendBytes(out, base + r.head_len, n);
  END;
END;

FUNCTION HttpExchange(fd: INTEGER32; VAR request: ByteBuf;
                      VAR raw: ByteBuf; VAR r: HttpResp;
                      max_head: INTEGER32;
                      timeout_ms: INTEGER32): INTEGER32;
VAR
  sent, total, got, outcome: INTEGER32;
BEGIN
  HttpRespInit(r);
  total := BufLen(request);
  sent := NetWrite(fd, request);
  IF sent <> total THEN
    outcome := HTTP_HEAD_ERROR
  ELSE
  BEGIN
    outcome := HttpReadRespHead(fd, raw, r, max_head, timeout_ms);
    IF outcome = HTTP_HEAD_OK THEN
    BEGIN
      IF r.malformed OR (r.content_length = HTTP_CL_MALFORMED) THEN
        outcome := HTTP_HEAD_BAD
      ELSE IF r.content_length = HTTP_CL_ABSENT THEN
      BEGIN
        { No Content-Length: in HTTP/1.0 the body runs to end of stream, so
          read until the peer closes. A timeout or error also ends the loop,
          and is not reported -- whatever arrived before it is the body, and
          there is no length to check it against. }
        got := 1;
        WHILE got > 0 DO
          got := NetRead(fd, raw, timeout_ms);
      END
      ELSE IF NOT HttpReadRespBody(fd, raw, r, r.content_length,
                                   timeout_ms) THEN
        outcome := HTTP_HEAD_EOF;
    END;
  END;
  HttpExchange := outcome;
END;

BEGIN
END.
