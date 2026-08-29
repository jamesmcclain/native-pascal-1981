(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'httpio.inc'*)
PROGRAM oneshot(input, output);
{ One upstream /chat/completions call, printed. The step-5 milestone of the
  proxy port, and the first program to put the whole client stack together:
  argparse for the flags, netsock for the connection, httpio for the exchange,
  jsonx for the payload and the reply.

  It is not the proxy and does not pretend to be -- no calibration, no echo
  stripping, no server side. What it does prove is that a request built here
  is one a real OpenAI-compatible backend accepts, and that its answer comes
  back intact. Run it against tests/proxy/stub_upstream.py for a deterministic
  answer, or against a live llama.cpp or LM Studio for a real one.

  The heading names only (input, output) on purpose: a program that lists more
  binds those names positionally to argv at startup and stops to prompt for
  any that are missing, which with a flag parser means a server that hangs
  before main ever runs. See argparse.inc.

  The completion is extracted here rather than in a unit because the rules for
  it -- content may be a plain string or a list of "type"/"text" parts, and a
  "length" finish with empty content is an error rather than an empty answer
  -- are the proxy's policy, and belong in proxycore when that exists. }
USES bytebuf, argparse, netsock, jsonx, httpio;

VAR
  base_url: ADRMEM;
  host, path, effort, model, s, why: ByteStr;
  { argparse's VAR outputs are its own ArgStr. It is the same LSTRING(255) as
    ByteStr, but the two are distinct named types: neither a VAR parameter nor
    even a plain assignment will take one for the other, so values cross by an
    explicit copy. Two units each naming their own 255-byte string type is the
    cost of keeping them independent, and a shared string type in the runtime
    library would remove it. }
  astr: ArgStr;
  port, timeout_ms, max_tokens, rc, i, fd, max_head: INTEGER32;
  payload, msgs, m, tree: ADRMEM;
  req, raw, body, text: ByteBuf;
  resp: HttpResp;

{ Append the completion to `out`. Returns FALSE when the reply carries no
  usable content, which includes the case that matters most in practice: a
  model that spent its whole budget on reasoning and finished with
  finish_reason "length" and nothing to show for it. That is an upstream
  failure, not an empty completion, and treating it as the latter is what
  makes a proxy answer 200 with nothing in it. }
{ Copy an argparse string into a bytebuf one, character by character, since
  the compiler will not do it for us. }
PROCEDURE ToByteStr(src: ArgStr; VAR dst: ByteStr);
VAR
  i, n: INTEGER;
BEGIN
  n := ORD(src[0]);
  dst[0] := CHR(n);
  FOR i := 1 TO n DO
    dst[i] := src[i];
END;

FUNCTION ExtractContent(tree: ADRMEM; VAR out: ByteBuf;
                        VAR why: ByteStr): BOOLEAN;
VAR
  choices, choice, message, content, part: ADRMEM;
  finish: ByteStr;
  i, n: INTEGER32;
  got: BOOLEAN;
BEGIN
  why := '';
  choices := JxGet(tree, 'choices');
  IF NOT JxIsArray(choices) THEN
  BEGIN
    why := 'no choices array';
    ExtractContent := FALSE;
    RETURN;
  END;
  IF JxArrSize(choices) = 0 THEN
  BEGIN
    why := 'choices array is empty';
    ExtractContent := FALSE;
    RETURN;
  END;
  choice := JxArrItem(choices, 0);
  message := JxGet(choice, 'message');
  content := JxGet(message, 'content');
  got := FALSE;
  IF JxIsString(content) THEN
    got := JxStrToBuf(content, out)
  ELSE IF JxIsArray(content) THEN
  BEGIN
    { The parts form: concatenate every text part, ignoring any other kind. }
    n := JxArrSize(content);
    FOR i := 0 TO n - 1 DO
    BEGIN
      part := JxArrItem(content, i);
      IF JxGetStrToBuf(part, 'text', out) THEN got := TRUE;
    END;
  END;
  IF BufLen(out) = 0 THEN
  BEGIN
    got := FALSE;
    JxGetStr(choice, 'finish_reason', finish);
    IF finish = 'length' THEN
      why := 'budget exhausted before any content'
    ELSE
      why := 'empty content';
  END;
  ExtractContent := got;
END;

BEGIN
  ArgBegin('oneshot', 'One /chat/completions call against an OpenAI-compatible backend.');
  ArgString('base-url', 'u', 'http://127.0.0.1:8080/v1',
            'upstream base URL, e.g. http://host:port/v1');
  ArgString('model', 'm', 'stub-model', 'model name to request');
  ArgString('prompt', 'p', 'complete this', 'user message to send');
  ArgString('system', ARG_NO_SHORT, 'You are a code completion engine.',
            'system message to send');
  ArgString('reasoning-effort', ARG_NO_SHORT, '',
            'reasoning_effort to send; omitted from the payload when empty');
  ArgInt('max-tokens', ARG_NO_SHORT, 256, 'max_tokens to request');
  ArgInt('timeout', 't', 20, 'upstream timeout in seconds');
  ArgFlag('show-request', ARG_NO_SHORT, 'print the payload before sending it');

  IF NOT ArgParse THEN
  BEGIN
    ArgError(astr);
    WRITELN('oneshot: ', astr);
    ArgUsage;
    NetExit(2);
  END;
  IF ArgHelpWanted THEN
  BEGIN
    ArgUsage;
    NetExit(0);
  END;

  NetInit;

  base_url := ArgGetRaw('base-url');
  IF NOT NetUrlSplit(base_url, host, port, path) THEN
  BEGIN
    WRITELN('oneshot: cannot parse --base-url (plain http only, no https)');
    NetExit(2);
  END;
  { The base URL names the API root; the endpoint hangs off it. A trailing
    slash on the root would otherwise produce a doubled one in the path. }
  IF (ORD(path[0]) > 0) AND (path[ORD(path[0])] = '/') THEN
    path[0] := CHR(ORD(path[0]) - 1);
  CONCAT(path, '/chat/completions');

  ArgGetStr('model', astr);
  ToByteStr(astr, model);
  timeout_ms := ArgGetInt('timeout') * 1000;
  max_tokens := ArgGetInt('max-tokens');

  payload := JxNewObject;
  JxAddStr(payload, 'model', model);
  JxAddInt(payload, 'max_tokens', max_tokens);
  JxAddNum(payload, 'temperature', 0.2);
  ArgGetStr('reasoning-effort', astr);
  ToByteStr(astr, effort);
  IF ORD(effort[0]) > 0 THEN
    JxAddStr(payload, 'reasoning_effort', effort);
  msgs := JxNewArray;
  m := JxNewObject;
  JxAddStr(m, 'role', 'system');
  ArgGetStr('system', astr);
  ToByteStr(astr, s);
  JxAddStr(m, 'content', s);
  JxArrAppend(msgs, m);
  m := JxNewObject;
  JxAddStr(m, 'role', 'user');
  { The prompt goes through the raw accessor, not the LSTRING one: a real
    buffer of source code is far longer than 255 characters, and truncating
    it here would silently change the question being asked. }
  BufInit(text, 0);
  BufAppendCStr(text, ArgGetRaw('prompt'));
  JxAddStrFromBuf(m, 'content', text);
  BufFree(text);
  JxArrAppend(msgs, m);
  JxAddItem(payload, 'messages', msgs);

  BufInit(text, 0);
  IF NOT JxPrintToBuf(payload, text) THEN
  BEGIN
    WRITELN('oneshot: could not serialize the payload');
    NetExit(1);
  END;
  IF ArgGetFlag('show-request') THEN
  BEGIN
    WRITE('request: ');
    FOR i := 0 TO BufLen(text) - 1 DO
      WRITE(BufAt(text, i));
    WRITELN;
  END;

  fd := NetConnect(host, port, timeout_ms);
  IF fd < 0 THEN
  BEGIN
    WRITELN('oneshot: cannot connect to ', host, ' port ', port);
    NetExit(1);
  END;

  BufInit(req, 0);
  HttpAppendRequestLine(req, 'POST', path);
  HttpAppendHeader(req, 'Host', host);
  HttpAppendHeader(req, 'Content-Type', 'application/json');
  HttpAppendHeaderInt(req, 'Content-Length', BufLen(text));
  HttpEndHeaders(req);
  BufAppendBuf(req, text);

  BufInit(raw, 0);
  { Built by arithmetic: an integer literal is 16 bits in this dialect, so
    writing 65000 here would pass -536 and disable the header ceiling. }
  max_head := 65;
  max_head := max_head * 1000;
  rc := HttpExchange(fd, req, raw, resp, max_head, timeout_ms);
  NetClose(fd);
  BufFree(req);
  BufFree(text);
  IF rc <> HTTP_HEAD_OK THEN
  BEGIN
    WRITELN('oneshot: upstream exchange failed, rc=', rc);
    NetExit(1);
  END;

  BufInit(body, 0);
  HttpRespBodyToBuf(raw, resp, body);
  IF resp.status <> 200 THEN
  BEGIN
    WRITELN('oneshot: upstream returned ', resp.status, ' ', resp.reason);
    { The body of an error is usually the only thing that says why. }
    FOR i := 0 TO BufLen(body) - 1 DO
      WRITE(BufAt(body, i));
    WRITELN;
    NetExit(1);
  END;

  tree := JxParseBuf(body);
  IF tree = NIL THEN
  BEGIN
    WRITELN('oneshot: upstream reply was not JSON');
    NetExit(1);
  END;

  JxGetStr(tree, 'model', s);
  WRITELN('model: ', s);

  BufInit(text, 0);
  IF NOT ExtractContent(tree, text, why) THEN
  BEGIN
    WRITELN('oneshot: no completion (', why, ')');
    NetExit(1);
  END;

  WRITELN('completion:');
  FOR i := 0 TO BufLen(text) - 1 DO
    WRITE(BufAt(text, i));
  WRITELN;
  WRITELN('bytes: ', BufLen(text));

  JxDelete(tree);
  JxDelete(payload);
  BufFree(text);
  BufFree(body);
  BufFree(raw);
END.
