(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'httpio.inc'*)
(*$INCLUDE:'proxycore.inc'*)
PROGRAM proxy(input, output);
{ The completion proxy pascal1981-mode talks to: POST /complete with a buffer
  and a cursor, out comes a completion from an OpenAI-compatible backend.

  This program is the composition root and holds only two things of its own:
  the command line, and the mapping from an outcome to an HTTP status. Both
  are policy, and both are pinned by tests/proxy/golden.json -- the mapping in
  particular is not the obvious one, and the comments below say why at each
  point where it surprises.

  One process per connection, not one thread. It is what the Python original
  did, deliberately, so that this port could match it: every request gets a
  fresh address space, so the allocations neither implementation frees are
  reclaimed by the kernel when the child exits, and a crash in one request
  cannot take the server down. The parent's accept loop allocates nothing.

  The heading names only (input, output). A program that lists more binds
  those names positionally to argv at startup and stops to prompt on stdin for
  any that are missing, which for a server means hanging before main runs.
  See argparse.inc. }
USES bytebuf, argparse, jsonx, netsock, httpio, proxycore;

CONST
  PX_MAX_HEAD = 65000;   { header block ceiling, per connection }

  { Upper bound on --upstream-timeout.  A day is far past anything useful for
    an editor completion, and it keeps the millisecond count well inside
    INTEGER32 (which tops out around 24.8 days), so the conversion in
    Configure cannot overflow. }
  PX_MAX_TIMEOUT_SECONDS = 86400.0;

VAR
  cfg: PxConfig;
  listen_fd, conn_fd, pid, bound_port: INTEGER32;
  astr: ArgStr;
  line: ByteBuf;

FUNCTION getenv(name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION pas_read_text_file(path: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE pas_eprint(msg: ADRMEM) [C]; EXTERN;
FUNCTION pas_double_to_int64(x: REAL): CLONG [C]; EXTERN;

{ argparse's VAR outputs are its own ArgStr: the same LSTRING(255) as ByteStr,
  but a distinct named type, so neither a VAR parameter nor an assignment will
  take one for the other. }
PROCEDURE ToByteStr(src: ArgStr; VAR dst: ByteStr);
VAR
  i, n: INTEGER;
BEGIN
  n := ORD(src[0]);
  dst[0] := CHR(n);
  FOR i := 1 TO n DO
    dst[i] := src[i];
END;

{ Progress and diagnostics go to stderr, never stdout: the harness that runs
  this discards stdout and reads stderr when startup fails. }
PROCEDURE Note(VAR text: ByteBuf);
BEGIN
  pas_eprint(BufCStr(text));
END;

PROCEDURE NoteStr(s: ByteStr);
VAR
  b: ByteBuf;
BEGIN
  BufInit(b, 0);
  BufAppendStr(b, 'pascal1981-completion-proxy: ');
  BufAppendStr(b, s);
  Note(b);
  BufFree(b);
END;

{ ------------------------------------------------------------------ }
{ Responses                                                           }
{ ------------------------------------------------------------------ }

PROCEDURE SendJson(fd: INTEGER32; status: INTEGER32; node: ADRMEM);
VAR
  body: ByteBuf;
  ok: BOOLEAN;
BEGIN
  BufInit(body, 0);
  IF NOT JxPrintToBuf(node, body) THEN
    BufAppendStr(body, '{}');
  ok := HttpWriteResponse(fd, status, 'application/json', body);
  BufFree(body);
END;

{ Every error answer has the same shape, which is what the client parses. }
PROCEDURE SendError(fd: INTEGER32; status: INTEGER32; message: ByteStr);
VAR
  node: ADRMEM;
BEGIN
  node := JxNewObject;
  JxAddStr(node, 'error', message);
  SendJson(fd, status, node);
  JxDelete(node);
END;

{ ------------------------------------------------------------------ }
{ GET /health                                                         }
{ ------------------------------------------------------------------ }

PROCEDURE HandleHealth(fd: INTEGER32);
VAR
  reply: PxReply;
  node: ADRMEM;
  url: ByteBuf;
  rc: INTEGER32;
BEGIN
  PxReplyInit(reply);
  rc := PxPing(cfg, reply);
  IF rc <> PX_UP_OK THEN
  BEGIN
    { 503, not 502: /health reports on this proxy's own readiness, and a
      backend it cannot use means the service is unavailable. }
    node := JxNewObject;
    JxAddStr(node, 'status', 'error');
    JxAddStr(node, 'error', reply.error);
    SendJson(fd, 503, node);
    JxDelete(node);
  END
  ELSE
  BEGIN
    BufInit(url, 0);
    PxUpstreamUrl(cfg, url);
    node := JxNewObject;
    JxAddStr(node, 'status', 'ok');
    JxAddStrFromBuf(node, 'upstream', url);
    { The model the backend reported, falling back to the one configured:
      most single-model servers echo nothing useful, and reporting an empty
      string would read as a failure. }
    IF BufLen(reply.model) > 0 THEN
      JxAddStrFromBuf(node, 'model', reply.model)
    ELSE
      JxAddStr(node, 'model', cfg.llm_model);
    JxAddStr(node, 'reasoning_effort', cfg.reasoning_effort);
    JxAddStrFromBuf(node, 'sample_completion', reply.text);
    SendJson(fd, 200, node);
    JxDelete(node);
    BufFree(url);
  END;
  PxReplyFree(reply);
END;

{ ------------------------------------------------------------------ }
{ POST /complete                                                      }
{ ------------------------------------------------------------------ }

PROCEDURE HandleComplete(fd: INTEGER32; VAR raw: ByteBuf; VAR req: HttpReq);
VAR
  body, prefix, prompt, stripped, clean: ByteBuf;
  tree, node, arr: ADRMEM;
  request: PxRequest;
  reply: PxReply;
  length, limit2, rc, i, n: INTEGER32;
  base: ADRMEM;
  has_text: BOOLEAN;
BEGIN
  length := req.content_length;
  IF length = HTTP_CL_MALFORMED THEN
  BEGIN
    SendError(fd, 400, 'invalid Content-Length header');
    RETURN;
  END;
  { An absent Content-Length counts as zero, and zero is too large. That
    reads backwards until you see the order: the size gate runs before any
    parsing, so a body of no bytes is rejected by the gate rather than by the
    JSON parser, and the gate answers 413. Pinned by empty_body and
    missing_content_length in the golden. }
  IF length = HTTP_CL_ABSENT THEN length := 0;
  limit2 := cfg.buffer_limit * 2;
  IF (length <= 0) OR (length > limit2) THEN
  BEGIN
    SendError(fd, 413, 'request body too large');
    RETURN;
  END;

  IF NOT HttpReadBody(fd, raw, req, length, cfg.timeout_ms) THEN
  BEGIN
    { The client promised more than it sent. Saying so beats the "invalid
      JSON" a short read would otherwise turn into. }
    SendError(fd, 400, 'request body was truncated');
    RETURN;
  END;

  BufInit(body, 0);
  base := BufPtr(raw);
  BufAppendBytes(body, base + req.head_len, length);

  { Python decodes the body before parsing it, so undecodable bytes are a 400
    there. cJSON does not check encoding at all, so the check is explicit
    here or the two implementations disagree. }
  IF NOT PxUtf8Valid(body) THEN
  BEGIN
    SendError(fd, 400, 'invalid JSON');
    BufFree(body);
    RETURN;
  END;

  tree := JxParseBuf(body);
  IF tree = NIL THEN
  BEGIN
    SendError(fd, 400, 'invalid JSON');
    BufFree(body);
    RETURN;
  END;

  PxRequestInit(request);
  IF NOT PxValidateRequest(tree, cfg.buffer_limit, request) THEN
  BEGIN
    SendError(fd, 400, request.error);
    PxRequestFree(request);
    JxDelete(tree);
    BufFree(body);
    RETURN;
  END;

  BufInit(prefix, 0);
  PxComputePrefix(request.buffer, request.line, request.column, prefix);
  BufInit(prompt, 0);
  PxBuildPrompt(request.goal, prefix, cfg.grammar, prompt);

  PxReplyInit(reply);
  rc := PxCallUpstream(cfg, prompt, cfg.reasoning_effort, cfg.temperature,
                       reply);
  IF rc <> PX_UP_OK THEN
  BEGIN
    { Every upstream failure is a 502, including budget exhaustion: from the
      client's side the request did not produce a completion, and the reason
      belongs in the message rather than in the status. }
    SendError(fd, 502, reply.error);
    PxReplyFree(reply);
    BufFree(prompt);
    BufFree(prefix);
    PxRequestFree(request);
    JxDelete(tree);
    BufFree(body);
    RETURN;
  END;

  { Echo stripping runs before the line cap, not after: the cap is meant to
    bound the completion the user gets, and stripping first is what decides
    which lines those are. }
  BufInit(stripped, 0);
  PxStripEcho(prefix, reply.text, stripped);
  BufInit(clean, 0);
  PxSanitizeCompletion(stripped, cfg.max_lines, clean);

  { An empty result is a normal outcome, not an error -- echo stripping can
    legitimately consume the whole candidate when the model only retyped the
    buffer. It is reported as an empty list rather than a list holding an
    empty string: a client cannot tell [""] from a real completion by length,
    and the editor answers one by drawing an empty ghost overlay, which reads
    as the key having done nothing. }
  has_text := FALSE;
  n := BufLen(clean);
  FOR i := 0 TO n - 1 DO
    IF ORD(BufAt(clean, i)) > 32 THEN has_text := TRUE;

  node := JxNewObject;
  arr := JxNewArray;
  IF has_text THEN
    JxArrAppend(arr, JxNewStrFromBuf(clean));
  JxAddItem(node, 'completions', arr);
  IF BufLen(reply.model) > 0 THEN
    JxAddStrFromBuf(node, 'model', reply.model)
  ELSE
    JxAddStr(node, 'model', cfg.llm_model);
  JxAddStrFromBuf(node, 'request_id', reply.request_id);
  SendJson(fd, 200, node);
  JxDelete(node);

  BufFree(clean);
  BufFree(stripped);
  PxReplyFree(reply);
  BufFree(prompt);
  BufFree(prefix);
  PxRequestFree(request);
  JxDelete(tree);
  BufFree(body);
END;

{ ------------------------------------------------------------------ }
{ One connection                                                      }
{ ------------------------------------------------------------------ }

PROCEDURE HandleConnection(fd: INTEGER32);
VAR
  raw: ByteBuf;
  req: HttpReq;
  rc: INTEGER32;
BEGIN
  BufInit(raw, 0);
  HttpReqInit(req);
  rc := HttpReadHead(fd, raw, req, PX_MAX_HEAD, cfg.timeout_ms);
  IF rc <> HTTP_HEAD_OK THEN
  BEGIN
    { A client that hung up or never finished its headers gets nothing: there
      is no request to answer, and writing to a half-open socket only earns a
      SIGPIPE. A header block over the ceiling does get told why. }
    IF rc = HTTP_HEAD_TOO_LARGE THEN
      SendError(fd, 413, 'request headers too large');
  END
  ELSE IF req.malformed THEN
    SendError(fd, 400, 'malformed request line')
  ELSE IF req.method = 'GET' THEN
  BEGIN
    IF req.path = '/health' THEN
      HandleHealth(fd)
    ELSE
      SendError(fd, 404, 'not found');
  END
  ELSE IF req.method = 'POST' THEN
  BEGIN
    IF req.path = '/complete' THEN
      HandleComplete(fd, raw, req)
    ELSE
      SendError(fd, 404, 'not found');
  END
  ELSE
    SendError(fd, 501, 'unsupported method');
  BufFree(raw);
END;

{ ------------------------------------------------------------------ }
{ Startup                                                             }
{ ------------------------------------------------------------------ }

{ Read a whole text file into `out`. Returns FALSE if it could not be read,
  which is worth reporting rather than silently proceeding without it: a
  --grammar-file that does not exist changes every prompt the proxy sends. }
FUNCTION LoadFile(path: ByteStr; VAR out: ByteBuf): BOOLEAN;
VAR
  cpath: ByteBuf;
  text: ADRMEM;
BEGIN
  BufInit(cpath, 0);
  BufAppendStr(cpath, path);
  text := pas_read_text_file(BufCStr(cpath));
  BufFree(cpath);
  IF text = NIL THEN
    LoadFile := FALSE
  ELSE
  BEGIN
    BufAppendCStr(out, text);
    LoadFile := TRUE;
  END;
END;

PROCEDURE DeclareOptions;
BEGIN
  ArgBegin('pascal1981-proxy',
           'Local HTTP proxy for pascal1981-mode LLM completion.');
  ArgString('host', ARG_NO_SHORT, '127.0.0.1',
            'host the proxy itself listens on');
  ArgInt('port', ARG_NO_SHORT, 8790, 'port the proxy itself listens on');
  ArgString('llm-base-url', ARG_NO_SHORT, 'http://127.0.0.1:8080/v1',
            'base URL of the OpenAI-compatible backend');
  ArgString('llm-model', ARG_NO_SHORT, 'default',
            'model name sent in every upstream request');
  ArgInt('buffer-limit', ARG_NO_SHORT, 65536,
         'maximum accepted "buffer" size, in characters');
  ArgInt('max-tokens', ARG_NO_SHORT, 512,
         'token budget per request, hidden reasoning included');
  ArgReal('temperature', ARG_NO_SHORT, 0.2, 'sampling temperature');
  ArgReal('upstream-timeout', ARG_NO_SHORT, 20.0,
          'seconds to wait for the backend; keep equal to the client''s own timeout');
  ArgString('reasoning-effort', ARG_NO_SHORT, 'auto',
            'none, low, medium, high, "" to omit, or auto to calibrate at startup');
  ArgString('grammar-file', ARG_NO_SHORT, '',
            'EBNF grammar to prepend to every prompt as context');
  ArgString('system-prompt-file', ARG_NO_SHORT, '',
            'text file overriding the completion system prompt');
  ArgInt('max-lines', ARG_NO_SHORT, PX_DEFAULT_MAX_LINES,
         'safety-valve cap on completion length, in lines');
END;

FUNCTION Configure(VAR host: ByteStr): BOOLEAN;
VAR
  url: ByteBuf;
  path: ByteStr;
  ok: BOOLEAN;
  timeout_s: REAL;
BEGIN
  PxConfigInit(cfg);
  ok := TRUE;

  ArgGetStr('host', astr);
  ToByteStr(astr, host);

  { The URL is split once here; every request needs the pieces. }
  BufInit(url, 0);
  BufAppendCStr(url, ArgGetRaw('llm-base-url'));
  IF NOT NetUrlSplit(BufCStr(url), cfg.upstream_host, cfg.upstream_port,
                     cfg.upstream_path) THEN
  BEGIN
    NoteStr('--llm-base-url could not be parsed (plain http only, no https)');
    ok := FALSE;
  END;
  BufFree(url);

  { A trailing slash on the API root would otherwise double up when the
    endpoint is appended. }
  IF ok THEN
    IF ORD(cfg.upstream_path[0]) > 1 THEN
      IF cfg.upstream_path[ORD(cfg.upstream_path[0])] = '/' THEN
        cfg.upstream_path[0] := CHR(ORD(cfg.upstream_path[0]) - 1);

  ArgGetStr('llm-model', astr);
  ToByteStr(astr, cfg.llm_model);
  ArgGetStr('reasoning-effort', astr);
  ToByteStr(astr, cfg.reasoning_effort);
  cfg.buffer_limit := ArgGetInt('buffer-limit');
  cfg.max_tokens := ArgGetInt('max-tokens');
  cfg.max_lines := ArgGetInt('max-lines');
  cfg.temperature := ArgGetReal('temperature');
  { Not TRUNC: it lowers to a 16-bit float-to-int conversion, so every timeout
    above 32.767 s -- the 20 s default is fine, but the corpus runs pass 60 --
    would be poison rather than a millisecond count, and that value goes
    straight to the socket as SO_RCVTIMEO.  pas_double_to_int64 clamps instead
    of leaving the conversion undefined, and PX_MAX_TIMEOUT_SECONDS keeps the
    milliseconds inside INTEGER32 so the narrowing is exact. }
  timeout_s := ArgGetReal('upstream-timeout');
  IF (timeout_s <= 0.0) OR (timeout_s > PX_MAX_TIMEOUT_SECONDS) THEN
  BEGIN
    NoteStr('--upstream-timeout must be greater than 0 and at most 86400 seconds');
    ok := FALSE;
  END
  ELSE
    cfg.timeout_ms := RETYPE(INTEGER32,
                             pas_double_to_int64(timeout_s * 1000.0));

  ArgGetStr('grammar-file', astr);
  ToByteStr(astr, path);
  IF ORD(path[0]) > 0 THEN
    IF NOT LoadFile(path, cfg.grammar) THEN
    BEGIN
      NoteStr('--grammar-file could not be read');
      ok := FALSE;
    END;

  ArgGetStr('system-prompt-file', astr);
  ToByteStr(astr, path);
  IF ORD(path[0]) > 0 THEN
  BEGIN
    BufClear(cfg.system_prompt);
    IF NOT LoadFile(path, cfg.system_prompt) THEN
    BEGIN
      NoteStr('--system-prompt-file could not be read');
      ok := FALSE;
    END;
  END;

  Configure := ok;
END;

{ The API key is environment-only and never a flag: a command line is readable
  by any other process on the machine, and shells persist it to history. }
PROCEDURE LoadApiKey;
VAR
  name: ByteBuf;
  found: ADRMEM;
BEGIN
  BufInit(name, 0);
  BufAppendStr(name, 'LLM_API_KEY');
  found := getenv(BufCStr(name));
  IF found <> NIL THEN
    BufAppendCStr(cfg.api_key, found);
  BufFree(name);
END;

VAR
  host: ByteStr;

BEGIN
  DeclareOptions;
  IF NOT ArgParse THEN
  BEGIN
    ArgError(astr);
    ToByteStr(astr, host);
    NoteStr(host);
    ArgUsage;
    NetExit(2);
  END;
  IF ArgHelpWanted THEN
  BEGIN
    ArgUsage;
    NetExit(0);
  END;

  IF NOT Configure(host) THEN NetExit(2);
  LoadApiKey;

  NetInit;

  { Calibration happens before the socket opens, so that the first request
    served is served with the value calibration chose. }
  IF cfg.reasoning_effort = 'auto' THEN
  BEGIN
    NoteStr('--reasoning-effort not set, calibrating against the backend');
    PxCalibrate(cfg, cfg.reasoning_effort);
  END;

  NetAutoReapChildren;
  listen_fd := NetListen(host, ArgGetInt('port'), 16);
  IF listen_fd < 0 THEN
  BEGIN
    NoteStr('could not listen on the requested host and port');
    NetExit(1);
  END;
  bound_port := NetPort(listen_fd);

  BufInit(line, 0);
  BufAppendStr(line, 'pascal1981-completion-proxy: listening on http://');
  BufAppendStr(line, host);
  BufAppendChar(line, ':');
  BufAppendInt(line, bound_port);
  BufAppendStr(line, '/complete, upstream ');
  PxUpstreamUrl(cfg, line);
  BufAppendStr(line, ', reasoning_effort=');
  IF ORD(cfg.reasoning_effort[0]) = 0 THEN
    BufAppendStr(line, '(omitted)')
  ELSE
    BufAppendStr(line, cfg.reasoning_effort);
  Note(line);
  BufFree(line);

  WHILE TRUE DO
  BEGIN
    conn_fd := NetAccept(listen_fd);
    IF conn_fd >= 0 THEN
    BEGIN
      pid := NetForkChild;
      IF pid = 0 THEN
      BEGIN
        { The child never accepts, so it must not hold the listening socket
          open: a client would otherwise keep the port alive after the parent
          exits. }
        NetClose(listen_fd);
        HandleConnection(conn_fd);
        NetShutdownWrite(conn_fd);
        NetClose(conn_fd);
        NetExit(0);
      END;
      NetClose(conn_fd);
    END;
  END;
END.
