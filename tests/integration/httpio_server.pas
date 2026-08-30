(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'httpio.inc'*)
PROGRAM httpio_server(input, output);
{ One request over a real socket: the parent listens, parses what arrives, and
  answers; a forked child sends the request and checks the response.

  Two connections. The first is an ordinary request; the second is a header
  block far larger than the ceiling the server allows, which is the only way
  to reach HTTP_HEAD_TOO_LARGE -- a path nothing exercised until a wrapped
  literal turned the ceiling negative and disabled it silently.

  The body is sent in a second write, deliberately separated from the headers,
  so the server cannot assume one read delivers a whole message. That is the
  realistic case -- a client writing headers and body separately, or a body
  large enough to be split -- and a parser that only worked when everything
  arrived at once would pass a simpler test and fail here.

  Only the parent prints, so the expected output does not depend on which
  process is scheduled first. The child reports through its exit status. }
USES bytebuf, netsock, httpio;

VAR
  listen_fd, conn_fd, client_fd, port, pid, status: INTEGER32;
  raw, body, reply: ByteBuf;
  req: HttpReq;
  head_rc, max_head, i: INTEGER32;
  ctype: ByteStr;

BEGIN
  NetInit;
  listen_fd := NetListen('127.0.0.1', 0, 16);
  IF listen_fd < 0 THEN
  BEGIN
    WRITELN('listen failed');
    NetExit(1);
  END;
  port := NetPort(listen_fd);

  pid := NetForkChild;
  IF pid = 0 THEN
  BEGIN
    NetClose(listen_fd);
    client_fd := NetConnect('127.0.0.1', port, 5000);
    IF client_fd < 0 THEN NetExit(2);

    BufInit(raw, 0);
    BufAppendStr(raw, 'POST /complete HTTP/1.1');
    HttpAppendCRLF(raw);
    BufAppendStr(raw, 'Host: 127.0.0.1');
    HttpAppendCRLF(raw);
    BufAppendStr(raw, 'Content-Type: application/json');
    HttpAppendCRLF(raw);
    BufAppendStr(raw, 'Content-Length: 17');
    HttpAppendCRLF(raw);
    HttpAppendCRLF(raw);
    IF NetWrite(client_fd, raw) < 0 THEN NetExit(3);

    { The body as a separate write: the server must keep reading. }
    BufClear(raw);
    BufAppendStr(raw, '{"goal":"finish"}');
    IF NetWrite(client_fd, raw) < 0 THEN NetExit(4);

    { Read the whole response and check it looks right. }
    BufClear(raw);
    WHILE NetRead(client_fd, raw, 5000) > 0 DO
      ;
    NetClose(client_fd);
    IF NOT BufMatchesStrAt(raw, 0, 'HTTP/1.0 200 OK') THEN NetExit(5);
    IF BufIndexOfStr(raw, 'Content-Length: 4', 0) < 0 THEN NetExit(6);
    IF BufIndexOfStr(raw, 'done', 0) < 0 THEN NetExit(7);
    NetClose(client_fd);

    { Second connection: a header block the server will refuse to keep
      reading. The blank line that would end it is never sent, so the only
      thing that can stop the server is its own ceiling. }
    client_fd := NetConnect('127.0.0.1', port, 5000);
    IF client_fd < 0 THEN NetExit(8);
    BufClear(raw);
    BufAppendStr(raw, 'GET /big HTTP/1.1');
    HttpAppendCRLF(raw);
    FOR i := 1 TO 40 DO
    BEGIN
      BufAppendStr(raw, 'X-Padding: ');
      BufAppendStr(raw,
        '0123456789012345678901234567890123456789012345678901234567890123');
      HttpAppendCRLF(raw);
    END;
    IF NetWrite(client_fd, raw) < 0 THEN NetExit(9);
    { Wait for the server to give up and close rather than exiting here,
      which would race the server's own read. }
    BufClear(raw);
    WHILE NetRead(client_fd, raw, 5000) > 0 DO
      ;
    NetClose(client_fd);
    NetExit(0);
  END;

  conn_fd := NetAccept(listen_fd);
  IF conn_fd < 0 THEN
  BEGIN
    WRITELN('accept failed');
    NetExit(1);
  END;

  BufInit(raw, 0);
  HttpReqInit(req);
  max_head := 65000;
  head_rc := HttpReadHead(conn_fd, raw, req, max_head, 5000);
  WRITELN('head-rc=', head_rc);
  WRITELN('method=', req.method, ' path=', req.path, ' version=', req.version);
  WRITELN('content-length=', req.content_length);
  WRITELN('ctype-found=', HttpHeaderValue(raw, req, 'content-type', ctype));
  WRITELN('ctype=', ctype);

  { Deliberately not asserting whether the body had already arrived with the
    headers: the child sends it as a separate write, but the kernel is free to
    coalesce the two into one segment, so that observation flips between runs.
    It was measured flipping 3 times in 5 here. What must hold either way is
    that the body is complete once HttpReadBody returns, which is what the
    next two lines check. }
  WRITELN('body-complete=', HttpReadBody(conn_fd, raw, req,
                                         req.content_length, 5000));
  WRITELN('body-len=', HttpBodyLen(raw, req));

  BufInit(body, 0);
  BufAppendStr(body, 'done');
  WRITELN('wrote=', HttpWriteResponse(conn_fd, 200, 'text/plain', body));
  NetClose(conn_fd);

  { Second connection, against a ceiling small enough that the padding
    overruns it. }
  conn_fd := NetAccept(listen_fd);
  IF conn_fd < 0 THEN
  BEGIN
    WRITELN('second accept failed');
    NetExit(1);
  END;
  BufClear(raw);
  HttpReqInit(req);
  head_rc := HttpReadHead(conn_fd, raw, req, 512, 5000);
  WRITELN('oversize-rc=', head_rc);
  NetClose(conn_fd);
  NetClose(listen_fd);

  status := NetWaitChild(pid);
  WRITELN('child-status=', status);
END.
