(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'httpio.inc'*)
PROGRAM httpio_client(input, output);
{ The client half of httpio, exercised against a server in a forked child:
  build a chat-completions request with jsonx, send it, read the framed
  response, and pull the completion back out.

  The child is the server and answers according to the path, so one run covers
  the four shapes that matter: an ordinary counted reply, a completion longer
  than an LSTRING can hold, a reply with no Content-Length at all (legal in
  HTTP/1.0, framed by the close), and an error status. The first case also
  echoes back two fields of the request the server actually received, which is
  the only way to prove the payload built here survived serialization, the
  wire, and parsing on the far side.

  Only the parent prints; the child reports through its exit status, so the
  expected output does not depend on which process runs first. }
USES bytebuf, netsock, jsonx, httpio;

VAR
  listen_fd, conn_fd, port, pid, status: INTEGER32;
  raw, body, reply_body, req_body: ByteBuf;
  resp: HttpResp;
  sreq: HttpReq;
  payload, msgs, msg, tree, reply, choice, content: ADRMEM;
  rc, i, want, served, max_head: INTEGER32;
  s: ByteStr;

{ ---- Client ---- }

{ Send one POST with `payload` as its body and leave the whole response in
  `raw`/`resp`. The payload is serialized here rather than by the caller so
  that every case goes out the same way. }
FUNCTION PostJson(port: INTEGER32; path: ByteStr; payload: ADRMEM;
                  VAR raw: ByteBuf; VAR resp: HttpResp): INTEGER32;
VAR
  fd, rc, max_head: INTEGER32;
  req, text: ByteBuf;
BEGIN
  { Not written as 65000: an integer literal is 16 bits here, so that value
    arrives as -536 and switches the ceiling off instead of setting it. }
  max_head := 65;
  max_head := max_head * 1000;
  fd := NetConnect('127.0.0.1', port, 5000);
  IF fd < 0 THEN
    PostJson := HTTP_HEAD_ERROR
  ELSE
  BEGIN
    BufInit(text, 0);
    IF NOT JxPrintToBuf(payload, text) THEN WRITELN('print failed');
    BufInit(req, 0);
    HttpAppendRequestLine(req, 'POST', path);
    HttpAppendHeader(req, 'Host', '127.0.0.1');
    HttpAppendHeader(req, 'Content-Type', 'application/json');
    HttpAppendHeaderInt(req, 'Content-Length', BufLen(text));
    HttpEndHeaders(req);
    BufAppendBuf(req, text);
    rc := HttpExchange(fd, req, raw, resp, max_head, 5000);
    NetClose(fd);
    BufFree(req);
    BufFree(text);
    PostJson := rc;
  END;
END;

{ The request every case sends: the chat-completions payload shape, built
  with jsonx because jsonutil cannot make the messages array. }
FUNCTION BuildPayload: ADRMEM;
VAR
  obj, arr, m: ADRMEM;
BEGIN
  obj := JxNewObject;
  JxAddStr(obj, 'model', 'stub-model');
  JxAddInt(obj, 'max_tokens', 64);
  arr := JxNewArray;
  m := JxNewObject;
  JxAddStr(m, 'role', 'system');
  JxAddStr(m, 'content', 'complete the code');
  JxArrAppend(arr, m);
  m := JxNewObject;
  JxAddStr(m, 'role', 'user');
  JxAddStr(m, 'content', 'PROGRAM p(output);');
  JxArrAppend(arr, m);
  JxAddItem(obj, 'messages', arr);
  BuildPayload := obj;
END;

BEGIN
  NetInit;
  max_head := 65;
  max_head := max_head * 1000;
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
    { ---- Child: a stub upstream, one canned reply per path ---- }
    served := 0;
    WHILE served < 4 DO
    BEGIN
      conn_fd := NetAccept(listen_fd);
      IF conn_fd < 0 THEN NetExit(2);
      BufInit(raw, 0);
      HttpReqInit(sreq);
      IF HttpReadHead(conn_fd, raw, sreq, max_head, 5000) <> HTTP_HEAD_OK THEN
        NetExit(3);
      want := sreq.content_length;
      IF want > 0 THEN
        IF NOT HttpReadBody(conn_fd, raw, sreq, want, 5000) THEN NetExit(4);

      BufInit(reply_body, 0);
      IF sreq.path = '/one' THEN
      BEGIN
        { Read the request back and quote two of its fields, so the parent
          can see what actually arrived rather than what it meant to send. }
        BufInit(req_body, 0);
        BufAppendBytes(req_body, BufPtr(raw) + sreq.head_len,
                       HttpBodyLen(raw, sreq));
        tree := JxParseBuf(req_body);
        reply := JxNewObject;
        JxGetStr(tree, 'model', s);
        JxAddStr(reply, 'seen_model', s);
        JxGetStr(JxArrItem(JxGet(tree, 'messages'), 1), 'content', s);
        JxAddStr(reply, 'seen_user', s);
        JxAddInt(reply, 'seen_bytes', HttpBodyLen(raw, sreq));
        choice := JxNewObject;
        msg := JxNewObject;
        JxAddStr(msg, 'role', 'assistant');
        JxAddStr(msg, 'content', 'WRITELN(1); END.');
        JxAddItem(choice, 'message', msg);
        JxAddStr(choice, 'finish_reason', 'stop');
        msgs := JxNewArray;
        JxArrAppend(msgs, choice);
        JxAddItem(reply, 'choices', msgs);
        JxAddStr(reply, 'model', 'stub-model');
        IF NOT JxPrintToBuf(reply, reply_body) THEN NetExit(5);
        JxDelete(reply);
        JxDelete(tree);
        BufFree(req_body);
        IF NOT HttpWriteResponse(conn_fd, 200, 'application/json',
                                 reply_body) THEN NetExit(6);
      END
      ELSE IF sreq.path = '/long' THEN
      BEGIN
        BufAppendStr(reply_body, '{"choices":[{"message":{"content":"');
        FOR i := 0 TO 299 DO
          BufAppendChar(reply_body, CHR(97 + (i MOD 26)));
        BufAppendStr(reply_body, '"}}]}');
        IF NOT HttpWriteResponse(conn_fd, 200, 'application/json',
                                 reply_body) THEN NetExit(7);
      END
      ELSE IF sreq.path = '/noclen' THEN
      BEGIN
        { A response with no Content-Length: HTTP/1.0 frames it by closing.
          Written by hand, since HttpWriteResponse always counts its body. }
        HttpAppendStatusLine(reply_body, 200);
        BufAppendStr(reply_body, 'Content-Type: application/json');
        HttpAppendCRLF(reply_body);
        BufAppendStr(reply_body, 'Connection: close');
        HttpAppendCRLF(reply_body);
        HttpAppendCRLF(reply_body);
        BufAppendStr(reply_body, '{"choices":[{"message":{"content":');
        BufAppendStr(reply_body, '"unframed"}}]}');
        IF NetWrite(conn_fd, reply_body) < 0 THEN NetExit(8);
      END
      ELSE
      BEGIN
        BufAppendStr(reply_body, '{"error":{"message":"no model loaded"}}');
        IF NOT HttpWriteResponse(conn_fd, 502, 'application/json',
                                 reply_body) THEN NetExit(9);
      END;

      NetClose(conn_fd);
      BufFree(reply_body);
      BufFree(raw);
      served := served + 1;
    END;
    NetExit(0);
  END;

  { ---- Parent: the client under test ---- }
  NetClose(listen_fd);

  { 1. An ordinary counted reply. }
  payload := BuildPayload;
  BufInit(raw, 0);
  rc := PostJson(port, '/one', payload, raw, resp);
  WRITELN('rc=', rc, ' status=', resp.status, ' reason=', resp.reason);
  WRITELN('version=', resp.version, ' clen=', resp.content_length);
  WRITELN('body_len=', HttpRespBodyLen(raw, resp));
  BufInit(body, 0);
  HttpRespBodyToBuf(raw, resp, body);
  tree := JxParseBuf(body);
  JxGetStr(tree, 'seen_model', s);
  WRITELN('seen_model=', s);
  JxGetStr(tree, 'seen_user', s);
  WRITELN('seen_user=', s);
  WRITELN('seen_bytes=', JxGetInt(tree, 'seen_bytes'));
  choice := JxArrItem(JxGet(tree, 'choices'), 0);
  JxGetStr(JxGet(choice, 'message'), 'content', s);
  WRITELN('content=', s);
  JxGetStr(choice, 'finish_reason', s);
  WRITELN('finish=', s);
  { Content-Type is a header the client is expected to be able to find. }
  IF HttpRespHeaderValue(raw, resp, 'content-type', s) THEN
    WRITELN('ctype=', s)
  ELSE
    WRITELN('ctype missing');
  JxDelete(tree);
  JxDelete(payload);
  BufFree(body);
  BufFree(raw);

  { 2. A completion past 255 characters, the case an LSTRING would eat. }
  payload := BuildPayload;
  BufInit(raw, 0);
  rc := PostJson(port, '/long', payload, raw, resp);
  BufInit(body, 0);
  HttpRespBodyToBuf(raw, resp, body);
  tree := JxParseBuf(body);
  choice := JxArrItem(JxGet(tree, 'choices'), 0);
  content := JxGet(JxGet(choice, 'message'), 'content');
  BufInit(reply_body, 0);
  WRITELN('long_rc=', rc, ' long_read=', JxStrToBuf(content, reply_body));
  WRITELN('long_len=', BufLen(reply_body),
          ' first=', BufAt(reply_body, 0),
          ' last=', BufAt(reply_body, BufLen(reply_body) - 1));
  JxDelete(tree);
  JxDelete(payload);
  BufFree(reply_body);
  BufFree(body);
  BufFree(raw);

  { 3. No Content-Length: the body runs to end of stream. }
  payload := BuildPayload;
  BufInit(raw, 0);
  rc := PostJson(port, '/noclen', payload, raw, resp);
  BufInit(body, 0);
  HttpRespBodyToBuf(raw, resp, body);
  tree := JxParseBuf(body);
  choice := JxArrItem(JxGet(tree, 'choices'), 0);
  JxGetStr(JxGet(choice, 'message'), 'content', s);
  WRITELN('noclen_rc=', rc, ' clen=', resp.content_length,
          ' body_len=', HttpRespBodyLen(raw, resp));
  WRITELN('noclen_content=', s);
  JxDelete(tree);
  JxDelete(payload);
  BufFree(body);
  BufFree(raw);

  { 4. An error status still parses; the status is the caller's business. }
  payload := BuildPayload;
  BufInit(raw, 0);
  rc := PostJson(port, '/boom', payload, raw, resp);
  BufInit(body, 0);
  HttpRespBodyToBuf(raw, resp, body);
  tree := JxParseBuf(body);
  JxGetStr(JxGet(tree, 'error'), 'message', s);
  WRITELN('err_rc=', rc, ' status=', resp.status, ' reason=', resp.reason);
  WRITELN('err_message=', s);
  JxDelete(tree);
  JxDelete(payload);
  BufFree(body);
  BufFree(raw);

  status := NetWaitChild(pid);
  WRITELN('child=', status);
END.
