{ IMPLEMENTATION of proxycore. See proxycore.inc for the contract, and in
  particular for how counting in bytes here differs from counting in
  characters in the Python original.

  The constants in the echo passes are calibrated, not chosen. Each one is
  explained where it is declared; none of them should be adjusted without a
  case that demonstrates the adjustment is right. }

(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'proxycore.inc'*)

IMPLEMENTATION OF proxycore;

CONST
  PX_TAB   = 9;
  PX_LF    = 10;
  PX_VT    = 11;
  PX_FF    = 12;
  PX_CR    = 13;
  PX_SPACE = 32;
  PX_DEL   = 127;

  { An exact overlap must be longer than this before it counts as an echo. A
    short overlap is ordinary, structurally required repetition rather than
    the model retyping something: two nested blocks closing back to back both
    correctly end in "END;". An earlier version of the original had no floor
    and ate real completions down to nothing, live in the editor. }
  PX_ECHO_MIN_OVERLAP = 5;

  { Floors for the approximate pass, both of which must be cleared. They are
    far stricter than the exact pass's floor because approximate matching can
    only ever make more things match: reusing the low floor here would bring
    back precisely the false positives that floor exists to prevent.

    "END;" is one token pair and 4 characters; two blocks closing in a row is
    4 tokens and 8; three in a row is 6 and 12. A retyped "total := total + j;"
    is 7 tokens and 15. So the floors sit between those: 7 tokens and 14
    characters admits the statement and excludes every run of up to three
    closers. Neither floor is redundant -- tokens alone would admit six
    one-character closers, characters alone two long identifiers. }
  PX_ECHO_MIN_APPROX_TOKENS = 7;
  PX_ECHO_MIN_APPROX_CHARS  = 14;

  { Token budget per side. The alignment is O(m*n), so this bounds its cost
    outright: 256 by 256 is trivially fast, and far longer than any echo a
    model with a few hundred output tokens can produce. An echo is the model
    retyping recent context; it does not reach back kilobytes. }
  PX_ECHO_MAX_TOKENS = 256;

TYPE
  PxTokenArr = ARRAY [1..PX_ECHO_MAX_TOKENS] OF INTEGER32;
  PxDistArr  = ARRAY [0..PX_ECHO_MAX_TOKENS] OF INTEGER32;

FUNCTION memcmp(a: ADRMEM; b: ADRMEM; n: CSIZE_T): CINT [C]; EXTERN;

{ ------------------------------------------------------------------ }
{ Byte classification                                                 }
{ ------------------------------------------------------------------ }

FUNCTION PxByte(VAR b: ByteBuf; i: INTEGER32): INTEGER32;
BEGIN
  PxByte := ORD(BufAt(b, i));
END;

FUNCTION PxIsSpaceOrd(v: INTEGER32): BOOLEAN;
BEGIN
  PxIsSpaceOrd := (v = PX_SPACE) OR (v = PX_TAB) OR (v = PX_LF) OR
                  (v = PX_CR) OR (v = PX_FF) OR (v = PX_VT);
END;

FUNCTION PxIsIdentOrd(v: INTEGER32): BOOLEAN;
BEGIN
  PxIsIdentOrd := ((v >= 48) AND (v <= 57)) OR
                  ((v >= 65) AND (v <= 90)) OR
                  ((v >= 97) AND (v <= 122)) OR (v = 95);
END;

FUNCTION PxLowerOrd(v: INTEGER32): INTEGER32;
BEGIN
  IF (v >= 65) AND (v <= 90) THEN
    PxLowerOrd := v + 32
  ELSE
    PxLowerOrd := v;
END;

{ A UTF-8 continuation byte: 10xxxxxx. Tested arithmetically because this
  dialect has no bitwise AND on integers. }
FUNCTION PxIsCont(v: INTEGER32): BOOLEAN;
BEGIN
  PxIsCont := (v >= 128) AND (v < 192);
END;

PROCEDURE PxAppendSlice(VAR src: ByteBuf; from: INTEGER32; count: INTEGER32;
                        VAR out: ByteBuf);
VAR
  base: ADRMEM;
BEGIN
  IF count > 0 THEN
  BEGIN
    base := BufPtr(src);
    BufAppendBytes(out, base + from, count);
  END;
END;

{ ------------------------------------------------------------------ }
{ Encoding                                                            }
{ ------------------------------------------------------------------ }

FUNCTION PxCharLen(VAR b: ByteBuf): INTEGER32;
VAR
  i, n, count: INTEGER32;
BEGIN
  n := BufLen(b);
  count := 0;
  FOR i := 0 TO n - 1 DO
    IF NOT PxIsCont(PxByte(b, i)) THEN count := count + 1;
  PxCharLen := count;
END;

FUNCTION PxUtf8Valid(VAR b: ByteBuf): BOOLEAN;
VAR
  i, n, v, need, lo, hi, j: INTEGER32;
  ok: BOOLEAN;
BEGIN
  n := BufLen(b);
  ok := TRUE;
  i := 0;
  WHILE (i < n) AND ok DO
  BEGIN
    v := PxByte(b, i);
    { The second byte's legal range varies with the first, and that is the
      whole of what rules out overlong forms, surrogates and anything past
      U+10FFFF -- the cases a length-only check would wave through and a
      real decoder rejects. }
    need := 0;
    lo := 128;
    hi := 191;
    IF v < 128 THEN
      need := 0
    ELSE IF (v >= 194) AND (v <= 223) THEN
      need := 1
    ELSE IF v = 224 THEN
    BEGIN need := 2; lo := 160; END
    ELSE IF ((v >= 225) AND (v <= 236)) OR (v = 238) OR (v = 239) THEN
      need := 2
    ELSE IF v = 237 THEN
    BEGIN need := 2; hi := 159; END      { no UTF-16 surrogates }
    ELSE IF v = 240 THEN
    BEGIN need := 3; lo := 144; END
    ELSE IF (v >= 241) AND (v <= 243) THEN
      need := 3
    ELSE IF v = 244 THEN
    BEGIN need := 3; hi := 143; END      { nothing above U+10FFFF }
    ELSE
      ok := FALSE;

    IF ok AND (need > 0) THEN
    BEGIN
      IF i + need >= n THEN
        ok := FALSE
      ELSE
      BEGIN
        v := PxByte(b, i + 1);
        IF (v < lo) OR (v > hi) THEN ok := FALSE;
        FOR j := 2 TO need DO
          IF ok THEN
            IF NOT PxIsCont(PxByte(b, i + j)) THEN ok := FALSE;
      END;
    END;
    i := i + need + 1;
  END;
  PxUtf8Valid := ok;
END;

{ An integer as text, for building a message that names a limit. }
PROCEDURE PxIntToStr(v: INTEGER32; VAR out: ByteStr);
VAR
  tmp: ByteBuf;
BEGIN
  BufInit(tmp, 0);
  BufAppendInt(tmp, v);
  BufSliceToStr(tmp, 0, BufLen(tmp), out);
  BufFree(tmp);
END;

{ ------------------------------------------------------------------ }
{ Request validation                                                  }
{ ------------------------------------------------------------------ }

PROCEDURE PxRequestInit(VAR r: PxRequest);
BEGIN
  BufInit(r.goal, 0);
  BufInit(r.buffer, 0);
  r.line := 1;
  r.column := 1;
  r.error := '';
END;

PROCEDURE PxRequestFree(VAR r: PxRequest);
BEGIN
  BufFree(r.goal);
  BufFree(r.buffer);
END;

{ A JSON number that stands for an integer, and is not a boolean. cJSON
  keeps no record of whether the literal was written 4 or 4.0, so the two
  are indistinguishable here where Python tells them apart and rejects the
  second. No client writes a cursor coordinate that way; a fractional one is
  still rejected. }
FUNCTION PxIsIntegral(node: ADRMEM): BOOLEAN;
VAR
  v: REAL;
BEGIN
  IF NOT JxIsNumber(node) THEN
    PxIsIntegral := FALSE
  ELSE
  BEGIN
    { Not TRUNC: it narrows to a 16-bit INTEGER, so 65536.0 would compare
      equal to 0 and a perfectly ordinary large value would be called
      fractional. }
    v := JxNumValue(node);
    PxIsIntegral := v = JxIntValue(node);
  END;
END;

FUNCTION PxValidateRequest(tree: ADRMEM; buffer_limit: INTEGER32;
                           VAR r: PxRequest): BOOLEAN;
VAR
  node: ADRMEM;
  cursor: ADRMEM;
  limit_text, message_text: ByteStr;
  ok: BOOLEAN;
BEGIN
  BufClear(r.goal);
  BufClear(r.buffer);
  r.line := 1;
  r.column := 1;
  r.error := '';
  ok := TRUE;

  IF NOT JxIsObject(tree) THEN
  BEGIN
    r.error := 'request body must be a JSON object';
    ok := FALSE;
  END;

  IF ok THEN
  BEGIN
    node := JxGet(tree, 'buffer');
    IF NOT JxIsString(node) THEN
    BEGIN
      r.error := '"buffer" must be a string';
      ok := FALSE;
    END
    ELSE
    BEGIN
      IF NOT JxStrToBuf(node, r.buffer) THEN ok := FALSE;
      IF PxCharLen(r.buffer) > buffer_limit THEN
      BEGIN
        { The limit is named in the message: a client that sends too much
          can only shrink its request usefully if it knows by how much. }
        { Built in a local because CONCAT will only write to a bare LSTRING
          variable, never to a record field. }
        message_text := '"buffer" exceeds the ';
        PxIntToStr(buffer_limit, limit_text);
        CONCAT(message_text, limit_text);
        CONCAT(message_text, '-character limit');
        r.error := message_text;
        ok := FALSE;
      END;
    END;
  END;

  IF ok THEN
  BEGIN
    node := JxGet(tree, 'goal');
    IF node <> NIL THEN
      IF JxIsString(node) THEN
      BEGIN
        IF NOT JxStrToBuf(node, r.goal) THEN ok := FALSE;
      END
      ELSE
      BEGIN
        r.error := '"goal" must be a string';
        ok := FALSE;
      END;
  END;

  IF ok THEN
  BEGIN
    cursor := JxGet(tree, 'cursor');
    IF NOT JxIsObject(cursor) THEN
    BEGIN
      r.error := '"cursor" must be an object with line/column';
      ok := FALSE;
    END
    ELSE
    BEGIN
      node := JxGet(cursor, 'line');
      IF JxIsBool(node) OR (NOT PxIsIntegral(node)) THEN
      BEGIN
        r.error := '"cursor.line" must be a positive integer';
        ok := FALSE;
      END
      ELSE
      BEGIN
        r.line := JxIntValue(node);
        IF r.line < 1 THEN
        BEGIN
          r.error := '"cursor.line" must be a positive integer';
          ok := FALSE;
        END;
      END;
    END;
  END;

  IF ok THEN
  BEGIN
    node := JxGet(cursor, 'column');
    IF JxIsBool(node) OR (NOT PxIsIntegral(node)) THEN
    BEGIN
      r.error := '"cursor.column" must be a positive integer';
      ok := FALSE;
    END
    ELSE
    BEGIN
      r.column := JxIntValue(node);
      IF r.column < 1 THEN
      BEGIN
        r.error := '"cursor.column" must be a positive integer';
        ok := FALSE;
      END;
    END;
  END;

  PxValidateRequest := ok;
END;

{ ------------------------------------------------------------------ }
{ Prompt construction                                                 }
{ ------------------------------------------------------------------ }

PROCEDURE PxComputePrefix(VAR buffer: ByteBuf; line: INTEGER32;
                          column: INTEGER32; VAR out: ByteBuf);
VAR
  n, i, nlines, want, seen, line_start, line_end, chars, cut: INTEGER32;
BEGIN
  n := BufLen(buffer);
  nlines := 1;
  FOR i := 0 TO n - 1 DO
    IF PxByte(buffer, i) = PX_LF THEN nlines := nlines + 1;

  want := line;
  IF want < 1 THEN want := 1;
  IF want > nlines THEN want := nlines;

  line_start := 0;
  seen := 0;
  i := 0;
  WHILE (seen < want - 1) AND (i < n) DO
  BEGIN
    IF PxByte(buffer, i) = PX_LF THEN
    BEGIN
      seen := seen + 1;
      line_start := i + 1;
    END;
    i := i + 1;
  END;

  line_end := line_start;
  WHILE (line_end < n) AND (PxByte(buffer, line_end) <> PX_LF) DO
    line_end := line_end + 1;

  { Advance column-1 characters into the line, never past its end. Counting
    characters rather than bytes is what keeps the cut off the middle of a
    multi-byte character. }
  chars := column - 1;
  IF chars < 0 THEN chars := 0;
  cut := line_start;
  WHILE (chars > 0) AND (cut < line_end) DO
  BEGIN
    cut := cut + 1;
    WHILE (cut < line_end) AND PxIsCont(PxByte(buffer, cut)) DO
      cut := cut + 1;
    chars := chars - 1;
  END;

  { Everything before the chosen line is already exactly the earlier lines
    plus their newlines, so the prefix is one contiguous slice rather than a
    rebuilt join. }
  PxAppendSlice(buffer, 0, cut, out);
END;

PROCEDURE PxSystemPrompt(VAR out: ByteBuf);
BEGIN
  BufAppendStr(out, 'Continue the Pascal program. Output only the new code.');
END;

{ Bounds of `b` with leading and trailing whitespace removed. }
PROCEDURE PxTrimBounds(VAR b: ByteBuf; VAR first: INTEGER32;
                       VAR last: INTEGER32);
VAR
  n: INTEGER32;
BEGIN
  n := BufLen(b);
  first := 0;
  WHILE (first < n) AND PxIsSpaceOrd(PxByte(b, first)) DO
    first := first + 1;
  last := n;
  WHILE (last > first) AND PxIsSpaceOrd(PxByte(b, last - 1)) DO
    last := last - 1;
END;

PROCEDURE PxBuildPrompt(VAR goal: ByteBuf; VAR prefix: ByteBuf;
                        VAR grammar: ByteBuf; VAR out: ByteBuf);
VAR
  gfirst, glast, i, v: INTEGER32;
BEGIN
  PxTrimBounds(grammar, gfirst, glast);
  IF glast > gfirst THEN
  BEGIN
    { Marked with plain '#' lines rather than a Pascal comment: the grammar
      contains both comment delimiter pairs itself, as repetition syntax and
      as worked examples, so either wrapper would be closed early by its own
      content. }
    BufAppendStr(out,
      '# --- Pascal 1981 EBNF grammar reference (context only, do not repeat) ---');
    BufAppendChar(out, CHR(PX_LF));
    PxAppendSlice(grammar, gfirst, glast - gfirst, out);
    BufAppendChar(out, CHR(PX_LF));
    BufAppendStr(out, '# --- end grammar reference ---');
    BufAppendChar(out, CHR(PX_LF));
    BufAppendChar(out, CHR(PX_LF));
  END;

  PxTrimBounds(goal, gfirst, glast);
  IF glast > gfirst THEN
  BEGIN
    { A one-line Pascal comment, newlines flattened to spaces so it cannot
      be mistaken for buffer content. }
    BufAppendStr(out, '{ ');
    FOR i := gfirst TO glast - 1 DO
    BEGIN
      v := PxByte(goal, i);
      IF v = PX_LF THEN
        BufAppendChar(out, ' ')
      ELSE
        BufAppendChar(out, CHR(v));
    END;
    BufAppendStr(out, ' }');
    BufAppendChar(out, CHR(PX_LF));
  END;

  PxAppendSlice(prefix, 0, BufLen(prefix), out);
END;

{ ------------------------------------------------------------------ }
{ Upstream reply                                                      }
{ ------------------------------------------------------------------ }

PROCEDURE PxReplyInit(VAR r: PxReply);
BEGIN
  BufInit(r.text, 0);
  BufInit(r.model, 0);
  BufInit(r.request_id, 0);
  r.error := '';
END;

PROCEDURE PxReplyFree(VAR r: PxReply);
BEGIN
  BufFree(r.text);
  BufFree(r.model);
  BufFree(r.request_id);
END;

PROCEDURE PxStripCodeFence(VAR text: ByteBuf; VAR out: ByteBuf);
VAR
  fence, nl, body_start, body_end, first, last, n: INTEGER32;
  body: ByteBuf;
BEGIN
  n := BufLen(text);
  fence := BufIndexOfStr(text, '```', 0);
  IF fence < 0 THEN
    PxAppendSlice(text, 0, n, out)
  ELSE
  BEGIN
    nl := BufIndexOfChar(text, CHR(PX_LF), fence);
    IF nl < 0 THEN
      { A lone fence with nothing after it opens no block. Whatever came
        before it is prose, and there is nothing else to keep. }
      PxAppendSlice(text, 0, fence, out)
    ELSE
    BEGIN
      { The opening fence line carries an info string ('```pascal'), never
        source, so it is skipped whole. An unterminated block still yields
        its contents: the model ran out of tokens, but what it wrote before
        that is real. }
      body_start := nl + 1;
      body_end := BufIndexOfStr(text, '```', body_start);
      IF body_end < 0 THEN body_end := n;
      BufInit(body, 0);
      PxAppendSlice(text, body_start, body_end - body_start, body);
      PxTrimBounds(body, first, last);
      PxAppendSlice(body, first, last - first, out);
      BufFree(body);
    END;
  END;
END;

FUNCTION PxExtractCompletion(tree: ADRMEM; VAR r: PxReply): INTEGER32;
VAR
  choices, choice, message, content, part: ADRMEM;
  reasoning: ADRMEM;
  finish: ByteStr;
  raw: ByteBuf;
  i, n, outcome: INTEGER32;
  is_text, exhausted, ignored: BOOLEAN;
BEGIN
  BufClear(r.text);
  BufClear(r.model);
  BufClear(r.request_id);
  r.error := '';
  outcome := PX_UP_OK;

  IF NOT JxIsObject(tree) THEN
  BEGIN
    { A backend answering with a bare array or string is not a crash here:
      it is an ordinary upstream failure and gets an ordinary report. }
    r.error := 'upstream response was not a JSON object';
    PxExtractCompletion := PX_UP_ERROR;
    RETURN;
  END;

  choices := JxGet(tree, 'choices');
  IF (NOT JxIsArray(choices)) OR (JxArrSize(choices) = 0) THEN
  BEGIN
    r.error := 'upstream response had no choices';
    PxExtractCompletion := PX_UP_ERROR;
    RETURN;
  END;

  choice := JxArrItem(choices, 0);
  IF NOT JxIsObject(choice) THEN choice := NIL;
  message := JxGet(choice, 'message');
  IF NOT JxIsObject(message) THEN message := NIL;
  content := JxGet(message, 'content');

  BufInit(raw, 0);
  is_text := FALSE;
  IF JxIsString(content) THEN
    is_text := JxStrToBuf(content, raw)
  ELSE IF JxIsArray(content) THEN
  BEGIN
    { Newer backends may send content as a list of typed parts instead of a
      bare string. Concatenating the text parts costs nothing and turns a
      hard failure on such a backend into a normal completion. }
    is_text := TRUE;
    n := JxArrSize(content);
    FOR i := 0 TO n - 1 DO
    BEGIN
      part := JxArrItem(content, i);
      IF JxIsObject(part) THEN
        IF JxIsString(JxGet(part, 'text')) THEN
          ignored := JxGetStrToBuf(part, 'text', raw);
    END;
  END;

  IF NOT is_text THEN
  BEGIN
    r.error := 'upstream choice had no message.content field';
    outcome := PX_UP_ERROR;
  END
  ELSE IF BufLen(raw) = 0 THEN
  BEGIN
    { Empty content with finish_reason "length" and a non-empty
      reasoning_content is the reasoning model that spent its whole budget
      thinking and never answered. Distinguishable and actionable, so it is
      reported rather than returned as an empty completion. }
    JxGetStr(choice, 'finish_reason', finish);
    reasoning := JxGet(message, 'reasoning_content');
    exhausted := FALSE;
    IF finish = 'length' THEN
      IF reasoning <> NIL THEN
        IF JxIsString(reasoning) THEN
          exhausted := JxStrLen(reasoning) > 0
        ELSE
          exhausted := NOT JxIsNull(reasoning);
    IF exhausted THEN
    BEGIN
      r.error := 'upstream spent its whole token budget on hidden reasoning and never answered; increase max_tokens or check reasoning_effort';
      outcome := PX_UP_EXHAUSTED;
    END;
  END;

  IF outcome = PX_UP_OK THEN
  BEGIN
    PxStripCodeFence(raw, r.text);
    IF JxIsString(JxGet(tree, 'model')) THEN
      IF NOT JxGetStrToBuf(tree, 'model', r.model) THEN BufClear(r.model);
    IF JxIsString(JxGet(tree, 'id')) THEN
      IF NOT JxGetStrToBuf(tree, 'id', r.request_id) THEN
        BufClear(r.request_id);
  END;

  BufFree(raw);
  PxExtractCompletion := outcome;
END;

{ ------------------------------------------------------------------ }
{ Output sanitization                                                 }
{ ------------------------------------------------------------------ }

PROCEDURE PxSanitizeCompletion(VAR text: ByteBuf; max_lines: INTEGER32;
                               VAR out: ByteBuf);
VAR
  tmp: ByteBuf;
  i, n, v, marker, start, limit, lines, chars, cut: INTEGER32;
  stop: BOOLEAN;
BEGIN
  { 1. Control characters. Only newline and tab survive: a stray carriage
       return from CRLF-flavoured training data lands as a literal ^M in the
       user's source, and an ESC begins something the editor renders as an
       escape sequence. DEL goes with them. }
  BufInit(tmp, 0);
  n := BufLen(text);
  FOR i := 0 TO n - 1 DO
  BEGIN
    v := PxByte(text, i);
    IF (v = PX_LF) OR (v = PX_TAB) THEN
      BufAppendChar(tmp, CHR(v))
    ELSE IF (v >= 32) AND (v <> PX_DEL) THEN
      BufAppendChar(tmp, CHR(v));
  END;

  { 2. Leaked special-token formatting. Some backends emit fragments of
       their internal channel markers into the completion. '<|' cannot occur
       in legitimate Pascal, so truncating there is a safe, backend-agnostic
       guard. }
  marker := BufIndexOfStr(tmp, '<|', 0);
  IF marker >= 0 THEN BufTruncate(tmp, marker);

  { 3. Leading blank lines. The editor previews only the first line until
       asked for more, so a completion opening with a blank line previews as
       nothing at all and reads as a key that did nothing. }
  n := BufLen(tmp);
  start := 0;
  WHILE (start < n) AND (PxByte(tmp, start) = PX_LF) DO
    start := start + 1;

  { 4. At most max_lines lines. A bound on a runaway response, not a way to
       keep completions short. }
  limit := max_lines;
  IF limit < 1 THEN limit := 1;
  lines := 1;
  cut := start;
  stop := FALSE;
  WHILE (cut < n) AND (NOT stop) DO
  BEGIN
    IF PxByte(tmp, cut) = PX_LF THEN
    BEGIN
      { The newline that would begin line limit+1 is where the text ends;
        it is not itself kept, which is what joining the first `limit` lines
        amounts to. }
      IF lines = limit THEN
        stop := TRUE
      ELSE
      BEGIN
        lines := lines + 1;
        cut := cut + 1;
      END;
    END
    ELSE
      cut := cut + 1;
  END;

  { 5. A hard character ceiling, counted in characters so the cut never
       lands inside one. }
  chars := 0;
  i := start;
  WHILE (i < cut) AND (chars < PX_MAX_COMPLETION_CHARS) DO
  BEGIN
    i := i + 1;
    WHILE (i < cut) AND PxIsCont(PxByte(tmp, i)) DO
      i := i + 1;
    chars := chars + 1;
  END;

  PxAppendSlice(tmp, start, i - start, out);
  BufFree(tmp);
END;


{ ------------------------------------------------------------------ }
{ Echo stripping                                                      }
{ ------------------------------------------------------------------ }

{ Pass 1. The longest exact overlap between a suffix of the buffer and a
  prefix of the candidate. }
FUNCTION PxExactOverlap(VAR buffer: ByteBuf;
                        VAR candidate: ByteBuf): INTEGER32;
VAR
  nb, nc, k, best: INTEGER32;
  bbase, cbase: ADRMEM;
BEGIN
  nb := BufLen(buffer);
  nc := BufLen(candidate);
  k := nb;
  IF nc < k THEN k := nc;
  best := 0;
  IF k > 0 THEN
  BEGIN
    bbase := BufPtr(buffer);
    cbase := BufPtr(candidate);
    WHILE (k > 0) AND (best = 0) DO
    BEGIN
      { memcmp, not a Pascal loop. The search is quadratic in the worst case
        -- a buffer and a candidate that are long runs of the same character
        -- and doing the innermost comparison one byte at a time through a
        function call turns milliseconds into seconds. The C library does
        the same work word at a time. }
      IF memcmp(bbase + (nb - k), cbase, RETYPE(CSIZE_T, k)) = 0 THEN
        best := k;
      k := k - 1;
    END;
  END;
  PxExactOverlap := best;
END;

{ Pass 2. The cursor sits part-way through a word and the model answers by
  retyping the whole word rather than continuing it: typing DISPO and asking
  for a completion gets back DISPOSE(p2); instead of SE(p2);, and accepting
  that puts DISPODISPOSE(p2); in the buffer.

  Neither other pass can see it. The exact pass finds the overlap -- DISPO is
  five characters -- but its floor requires more than that, and a partial
  identifier is routinely shorter; lowering the floor is not an option, since
  four characters is END; and that floor is the only thing keeping
  legitimate structural repetition out. The token pass cannot see it either:
  DISPO and DISPOSE are simply different tokens to it.

  Being anchored to a word boundary on both sides is what makes a low
  threshold safe here where it would not be elsewhere. A candidate that
  correctly continues the partial word does not begin with it, and is left
  alone. }
FUNCTION PxPartialTokenCut(VAR buffer: ByteBuf;
                           VAR candidate: ByteBuf): INTEGER32;
VAR
  nb, nc, start, plen, head_end, i, cut: INTEGER32;
  match: BOOLEAN;
BEGIN
  nb := BufLen(buffer);
  start := nb;
  WHILE (start > 0) AND PxIsIdentOrd(PxByte(buffer, start - 1)) DO
    start := start - 1;
  plen := nb - start;
  cut := 0;
  IF plen > 0 THEN
  BEGIN
    nc := BufLen(candidate);
    head_end := 0;
    WHILE (head_end < nc) AND PxIsIdentOrd(PxByte(candidate, head_end)) DO
      head_end := head_end + 1;
    IF head_end >= plen THEN
    BEGIN
      { Case-insensitively, since the dialect is: dispose continues DISPO. }
      match := TRUE;
      FOR i := 0 TO plen - 1 DO
        IF PxLowerOrd(PxByte(buffer, start + i)) <>
           PxLowerOrd(PxByte(candidate, i)) THEN
          match := FALSE;
      IF match THEN cut := plen;
    END;
  END;
  PxPartialTokenCut := cut;
END;

{ Split into tokens for comparison: a case-folded run of identifier
  characters, or a single punctuation character, with whitespace dropped
  entirely. Each token is recorded as its half-open range in the raw text, so
  it is its own lowercase form for comparison purposes and a match measured
  in tokens maps straight back to a cut point in the raw text.

  Tokenizing rather than comparing characters is what makes indentation and
  keyword casing structurally invisible instead of something the comparison
  has to tolerate: this dialect is case-insensitive, so begin and BEGIN are
  the same token, and a model that reindents what it retypes has still
  echoed.

  keep_tail chooses which end to keep when there are more tokens than the
  budget: the buffer's last ones, since the echo is of what precedes the
  cursor, and the candidate's first ones, since an echo is a prefix of it. }
PROCEDURE PxTokenize(VAR b: ByteBuf; keep_tail: BOOLEAN;
                     VAR starts: PxTokenArr; VAR ends: PxTokenArr;
                     VAR count: INTEGER32);
VAR
  ring_s, ring_e: PxTokenArr;
  i, j, n, run, v, total, slot, offset: INTEGER32;
  stop: BOOLEAN;
BEGIN
  n := BufLen(b);
  total := 0;
  i := 0;
  stop := FALSE;
  WHILE (i < n) AND (NOT stop) DO
  BEGIN
    v := PxByte(b, i);
    IF PxIsSpaceOrd(v) THEN
      i := i + 1
    ELSE
    BEGIN
      IF PxIsIdentOrd(v) THEN
      BEGIN
        run := i;
        WHILE (run < n) AND PxIsIdentOrd(PxByte(b, run)) DO
          run := run + 1;
      END
      ELSE
        run := i + 1;
      { A ring, so keeping the last N costs no more than keeping the first. }
      slot := (total MOD PX_ECHO_MAX_TOKENS) + 1;
      ring_s[slot] := i;
      ring_e[slot] := run;
      total := total + 1;
      i := run;
      IF (NOT keep_tail) AND (total = PX_ECHO_MAX_TOKENS) THEN stop := TRUE;
    END;
  END;

  IF total <= PX_ECHO_MAX_TOKENS THEN
  BEGIN
    count := total;
    FOR j := 1 TO count DO
    BEGIN
      starts[j] := ring_s[j];
      ends[j] := ring_e[j];
    END;
  END
  ELSE
  BEGIN
    count := PX_ECHO_MAX_TOKENS;
    offset := total MOD PX_ECHO_MAX_TOKENS;
    FOR j := 1 TO count DO
    BEGIN
      slot := ((offset + j - 1) MOD PX_ECHO_MAX_TOKENS) + 1;
      starts[j] := ring_s[slot];
      ends[j] := ring_e[slot];
    END;
  END;
END;

FUNCTION PxTokEq(VAR a: ByteBuf; astart: INTEGER32; aend: INTEGER32;
                 VAR b: ByteBuf; bstart: INTEGER32;
                 bend: INTEGER32): BOOLEAN;
VAR
  i, n: INTEGER32;
  eq: BOOLEAN;
BEGIN
  n := aend - astart;
  IF n <> bend - bstart THEN
    eq := FALSE
  ELSE
  BEGIN
    eq := TRUE;
    i := 0;
    WHILE (i < n) AND eq DO
    BEGIN
      IF PxLowerOrd(PxByte(a, astart + i)) <>
         PxLowerOrd(PxByte(b, bstart + i)) THEN
        eq := FALSE;
      i := i + 1;
    END;
  END;
  PxTokEq := eq;
END;

{ Pass 3. An index into the candidate just past an approximate echo of the
  buffer's tail, or 0.

  The exact pass only catches an echo reproduced byte for byte, and a small
  model routinely does not: it retypes the last statement with its own
  indentation, re-cases keywords, renames a loop variable, drops a modifier.
  Any one of those collapses an exact match to nothing, and matching on
  normalized text is no better -- it still fails on the first substituted or
  missing token.

  So this is an overlap alignment: the minimum edit distance between some
  suffix of the buffer's token stream and each prefix of the candidate's.
  Zeroing the first column makes starting the buffer-side alignment at any
  token free, which is the "some suffix" part, and only the final row is
  meaningful -- the buffer ends at the cursor, which is exactly where the
  model resumed writing, so the echo must run to the buffer's end. }
FUNCTION PxApproxEchoCut(VAR buffer: ByteBuf;
                         VAR candidate: ByteBuf): INTEGER32;
VAR
  bs, be, cs, ce: PxTokenArr;
  prev, cur: PxDistArr;
  bcount, ccount, i, j, cost, best, chars: INTEGER32;
  cut, best_d, best_j: INTEGER32;
  have: BOOLEAN;
BEGIN
  PxTokenize(buffer, TRUE, bs, be, bcount);
  PxTokenize(candidate, FALSE, cs, ce, ccount);
  IF (bcount = 0) OR (ccount = 0) THEN
  BEGIN
    PxApproxEchoCut := 0;
    RETURN;
  END;

  { prev[j] starts as the cost of aligning an empty buffer suffix against
    the candidate's first j tokens: j insertions. }
  FOR j := 0 TO ccount DO
    prev[j] := j;
  FOR i := 1 TO bcount DO
  BEGIN
    cur[0] := 0;
    FOR j := 1 TO ccount DO
    BEGIN
      IF PxTokEq(buffer, bs[i], be[i], candidate, cs[j], ce[j]) THEN
        cost := 0
      ELSE
        cost := 1;
      best := prev[j] + 1;
      IF cur[j - 1] + 1 < best THEN best := cur[j - 1] + 1;
      IF prev[j - 1] + cost < best THEN best := prev[j - 1] + cost;
      cur[j] := best;
    END;
    FOR j := 0 TO ccount DO
      prev[j] := cur[j];
  END;

  { Take the cheapest qualifying alignment, breaking ties toward the longest
    -- not simply the longest that clears the threshold. Those are different
    choices and the difference is a real over-strip: where the candidate
    echoes seven tokens and then begins its own contribution, extending the
    match to eight costs one insertion but still scores 1 - 1/8, comfortably
    over the bar, and longest-wins would take it and eat the first token of
    the real completion. Ranking by distance first refuses that, because
    extending into new material always costs. }
  cut := 0;
  have := FALSE;
  best_d := 0;
  best_j := 0;
  chars := 0;
  FOR j := 1 TO ccount DO
  BEGIN
    chars := chars + (ce[j] - cs[j]);
    IF (j >= PX_ECHO_MIN_APPROX_TOKENS) AND
       (chars >= PX_ECHO_MIN_APPROX_CHARS) THEN
      { Similarity as integers: 1 - d/j >= 0.8 is exactly j >= 5*d, which
        avoids asking whether a float comparison lands on the right side of
        the threshold at the boundary. }
      IF j >= 5 * prev[j] THEN
        IF (NOT have) OR (prev[j] < best_d) OR
           ((prev[j] = best_d) AND (j > best_j)) THEN
        BEGIN
          have := TRUE;
          best_d := prev[j];
          best_j := j;
          cut := ce[j];
        END;
  END;
  PxApproxEchoCut := cut;
END;

PROCEDURE PxStripEcho(VAR buffer: ByteBuf; VAR candidate: ByteBuf;
                      VAR out: ByteBuf);
VAR
  cut: INTEGER32;
BEGIN
  cut := PxExactOverlap(buffer, candidate);
  IF cut <= PX_ECHO_MIN_OVERLAP THEN
  BEGIN
    cut := PxPartialTokenCut(buffer, candidate);
    IF cut = 0 THEN
      cut := PxApproxEchoCut(buffer, candidate);
  END;
  PxAppendSlice(candidate, cut, BufLen(candidate) - cut, out);
END;

BEGIN
END.
