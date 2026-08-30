{ INTERFACE header for proxycore, the completion proxy's transforms.

  Everything here is a pure function of its inputs: a request goes in, a
  prompt or a completion comes out, and nothing touches a socket. That is
  deliberate, and it is what makes the port testable -- each of these can be
  checked against the Python implementation it replaces, one input at a time,
  without a server running at either end. The HTTP plumbing lives in httpio
  and the policy that maps these outcomes onto status codes lives in the
  program itself.

  Everything is a ByteBuf rather than an LSTRING. A completion, a source
  buffer and a prompt are all routinely tens of kilobytes, and every one of
  them would be silently cut to 255 characters otherwise.

  BYTES VERSUS CHARACTERS. The Python original is a Unicode program: its
  buffer limit, its cursor column and its completion ceiling are all counted
  in characters, while the HTTP body gate that precedes them counts bytes.
  This port works in bytes throughout, and closes that gap where it is
  visible rather than pretending it is not:

  * Anything counted in characters upstream is counted here by counting UTF-8
    lead bytes (PxCharLen), so the numbers agree for any valid UTF-8 input,
    and a cut made on a character count never lands inside a character.
  * The echo-stripping floors are the exception, and are counted in bytes. In
    ASCII -- which is all Pascal 1981 source can be -- the two are the same
    thing. On text with multi-byte characters a floor is reached slightly
    sooner here. The floors exist to exclude short runs of structural
    punctuation, all of it ASCII, so the difference does not touch what they
    are for.
  * Identifier characters are ASCII letters, digits and underscore. Python's
    isalnum() would also accept a letter from any other script; no Pascal
    1981 identifier can contain one.
  * PxUtf8Valid exists because the boundary moved. Python decodes the body
    before parsing it, so undecodable bytes are rejected there; cJSON does
    not check encoding at all, so a request that would have been a 400
    upstream would otherwise sail through here.

  Requires bytebuf, jsonx, netsock and httpio. The upstream call lives here
  rather than in the program because calibration needs it too, and because
  the mapping from an upstream failure to a message the client may see is
  policy, which is what this unit is for. }

INTERFACE;
UNIT proxycore (PxRequestInit, PxRequestFree, PxValidateRequest,
                PxComputePrefix, PxBuildPrompt,
                PxReplyInit, PxReplyFree, PxExtractCompletion,
                PxStripCodeFence, PxStripEcho, PxSanitizeCompletion,
                PxUtf8Valid, PxCharLen, PxSystemPrompt,
                PxConfigInit, PxConfigFree, PxUpstreamUrl, PxChatUrlPath,
                PxCallUpstream, PxProbePrompt, PxPing, PxCalibrate,
                PxRequest, PxReply, PxConfig,
                PX_UP_OK, PX_UP_ERROR, PX_UP_EXHAUSTED,
                PX_MAX_COMPLETION_CHARS, PX_DEFAULT_MAX_LINES);

USES bytebuf, jsonx, netsock, httpio;

CONST
  { PxExtractCompletion outcomes. Exhaustion is a distinct outcome, not just
    another error, because calibration needs to tell "this reasoning_effort
    value is wrong for this model, try the next one" from "the backend is
    broken, stop trying" -- four more attempts against a dead backend only
    multiply the wait. }
  PX_UP_OK        = 0;
  PX_UP_ERROR     = 1;
  PX_UP_EXHAUSTED = 2;

  { Hard ceiling on a completion, in characters. max_lines bounds how many
    lines there are and says nothing about how long they are, so it does not
    bound this at all: one unterminated string literal of 200,000 characters
    is a single line, and it stalls redisplay in the editor that receives it.
    Far above any real completion; a safety valve, not a quality lever. }
  PX_MAX_COMPLETION_CHARS = 8192;
  PX_DEFAULT_MAX_LINES    = 30;

TYPE
  { Everything the proxy was configured with. The upstream URL arrives as one
    string and is split once at startup, because every request needs the
    pieces and nothing needs the URL back except /health, which rebuilds it. }
  PxConfig = RECORD
    upstream_host:    ByteStr;
    upstream_port:    INTEGER32;
    upstream_path:    ByteStr;   { the API root, no trailing slash }
    llm_model:        ByteStr;
    reasoning_effort: ByteStr;   { '' omits the field; 'auto' means calibrate }
    buffer_limit:     INTEGER32; { in characters, as the client counts them }
    max_tokens:       INTEGER32;
    max_lines:        INTEGER32;
    timeout_ms:       INTEGER32;
    temperature:      REAL;
    api_key:          ByteBuf;   { from the environment only, never a flag }
    grammar:          ByteBuf;   { optional EBNF context, usually empty }
    system_prompt:    ByteBuf;
  END;

  { A validated /complete request. The buffers are owned by the record: call
    PxRequestInit before use and PxRequestFree after. }
  PxRequest = RECORD
    goal:   ByteBuf;
    buffer: ByteBuf;
    line:   INTEGER32;    { 1-based, as the client sends it }
    column: INTEGER32;
    error:  ByteStr;      { empty unless validation failed; safe to return }
  END;

  { What an upstream /chat/completions reply yielded. Same ownership rule. }
  PxReply = RECORD
    text:       ByteBuf;   { the completion, code fence already stripped }
    model:      ByteBuf;
    request_id: ByteBuf;
    error:      ByteStr;   { empty unless the outcome was not PX_UP_OK }
  END;

{ ---- Configuration and the upstream call ---- }

PROCEDURE PxConfigInit(VAR c: PxConfig);
PROCEDURE PxConfigFree(VAR c: PxConfig);

{ The full chat-completions URL, as /health reports it. }
PROCEDURE PxUpstreamUrl(VAR c: PxConfig; VAR out: ByteBuf);

{ Just its path component, which is what a request line needs. }
PROCEDURE PxChatUrlPath(VAR c: PxConfig; VAR out: ByteStr);

{ One /chat/completions call. Returns a PX_UP_ constant; on anything but
  PX_UP_OK, reply.error carries a message safe to return to the client -- it
  names the failure without quoting the upstream's body or revealing the API
  key.

  `effort` and `temperature` are passed rather than taken from the config so
  that a probe can vary them without disturbing configured behaviour. An
  empty effort omits the field, and 'auto' is treated the same way: it is a
  sentinel for "calibrate", never a value to send. }
FUNCTION PxCallUpstream(VAR c: PxConfig; VAR prompt: ByteBuf;
                        effort: ByteStr; temperature: REAL;
                        VAR reply: PxReply): INTEGER32;

{ The prompt both probes use: a real /complete-shaped request, including the
  configured grammar context, because that materially changes prompt size and
  therefore reasoning cost. A generic one-line probe gives a false "it works"
  signal -- a reasoning model can answer a trivial sentence and still exhaust
  its budget on the Pascal completion a real request sends. }
PROCEDURE PxProbePrompt(VAR c: PxConfig; VAR out: ByteBuf);

{ One real call with the configured settings, for /health. As expensive as a
  real request on purpose: a tiny probe budget reports "not responding" on a
  backend that needs its whole budget just to finish thinking, which is not
  the question /health is asked. }
FUNCTION PxPing(VAR c: PxConfig; VAR reply: PxReply): INTEGER32;

{ Resolve reasoning_effort against the live backend. Tries none, low, medium,
  high and omitted in that order, first success winning, and never fails hard
  -- calibration not finding an answer is no reason to refuse to start.

  A backend error that is not budget exhaustion stops the search immediately
  and falls back to 'none': trying four more candidates against a backend
  that is down only multiplies the timeout wait. }
PROCEDURE PxCalibrate(VAR c: PxConfig; VAR chosen: ByteStr);

{ ---- Encoding helpers ---- }

{ TRUE when the whole buffer is well-formed UTF-8. Overlong encodings,
  surrogates and values above U+10FFFF are rejected, matching what Python's
  decoder refuses rather than only what a naive length check would catch. }
FUNCTION PxUtf8Valid(VAR b: ByteBuf): BOOLEAN;

{ Characters, not bytes: the count of UTF-8 lead bytes. On invalid input this
  is still well defined and simply counts non-continuation bytes. }
FUNCTION PxCharLen(VAR b: ByteBuf): INTEGER32;

{ ---- Request side ---- }

PROCEDURE PxRequestInit(VAR r: PxRequest);
PROCEDURE PxRequestFree(VAR r: PxRequest);

{ Validate a parsed /complete body. On FALSE, r.error carries a message that
  is safe to hand back to the client verbatim -- it says only what was wrong
  with the request, never anything about the upstream or the environment. }
FUNCTION PxValidateRequest(tree: ADRMEM; buffer_limit: INTEGER32;
                           VAR r: PxRequest): BOOLEAN;

{ The text from the start of `buffer` through the 1-based line/column point.

  Both coordinates are clamped to the buffer rather than rejected: a cursor
  past the end is a race between typing and requesting, not a client error. }
PROCEDURE PxComputePrefix(VAR buffer: ByteBuf; line: INTEGER32;
                          column: INTEGER32; VAR out: ByteBuf);

{ The user message sent upstream: mostly the prefix verbatim, so the model
  sees "the code so far" to continue. A non-empty goal precedes it as a
  one-line Pascal comment. A non-empty grammar precedes everything, fenced
  with plain '#' lines rather than a Pascal comment because the grammar text
  contains both comment delimiter pairs itself and would close either one
  early. }
PROCEDURE PxBuildPrompt(VAR goal: ByteBuf; VAR prefix: ByteBuf;
                        VAR grammar: ByteBuf; VAR out: ByteBuf);

{ The system message that accompanies it. }
PROCEDURE PxSystemPrompt(VAR out: ByteBuf);

{ ---- Reply side ---- }

PROCEDURE PxReplyInit(VAR r: PxReply);
PROCEDURE PxReplyFree(VAR r: PxReply);

{ Pull the completion, model and request id out of a /chat/completions body.
  Returns one of the PX_UP_ constants. }
FUNCTION PxExtractCompletion(tree: ADRMEM; VAR r: PxReply): INTEGER32;

{ The contents of the first markdown-fenced block, or the text unchanged when
  there is no fence. The fence is looked for anywhere, not only at the start:
  a small model very often answers with a prose preamble ahead of it, and
  keeping the preamble puts an English sentence in the user's source file. }
PROCEDURE PxStripCodeFence(VAR text: ByteBuf; VAR out: ByteBuf);

{ Strip an echoed prefix of the buffer's tail from the front of the
  candidate, returning the residue.

  Three passes, cheapest and strictest first, first hit winning: an exact
  character-level overlap, then a restated partial identifier, then an
  approximate token-level alignment. Each catches something the others
  structurally cannot; see the implementation for what, and for why the
  approximate pass carries much stricter floors than the exact one. }
PROCEDURE PxStripEcho(VAR buffer: ByteBuf; VAR candidate: ByteBuf;
                      VAR out: ByteBuf);

{ Enforce the output policy: no control characters other than newline and
  tab, nothing from a special-token marker onward, no leading blank lines, at
  most max_lines lines, at most PX_MAX_COMPLETION_CHARS characters. }
PROCEDURE PxSanitizeCompletion(VAR text: ByteBuf; max_lines: INTEGER32;
                               VAR out: ByteBuf);

END;
