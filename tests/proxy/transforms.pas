(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'proxycore.inc'*)
PROGRAM transforms(input, output);
{ A driver for differential testing of proxycore's pure transforms.

  Reads a JSON array of jobs on stdin and writes a JSON array of results on
  stdout, one per job. transforms_check.py feeds the same jobs to the Python
  implementation this port replaces and compares the two answers. That is a
  much stronger check than a hand-written golden: the expected values are
  computed by the code being replaced, so a case nobody thought of still
  counts, and the corpus can be extended without anyone having to work out by
  hand what the answer should be.

  Each job is an object with an "op" naming the transform; the other keys are
  its arguments. Anything unrecognised comes back as an error result rather
  than aborting, so one bad job does not lose the whole run. }
USES bytebuf, jsonx, proxycore;

VAR
  input_buf: ByteBuf;
  out_buf: ByteBuf;
  jobs, results, job, result_obj: ADRMEM;
  i, n: INTEGER32;

FUNCTION getchar: CINT [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;

PROCEDURE ReadAll(VAR into: ByteBuf);
VAR
  c: CINT;
BEGIN
  c := getchar;
  WHILE c <> -1 DO
  BEGIN
    BufAppendChar(into, CHR(RETYPE(INTEGER32, c)));
    c := getchar;
  END;
END;

{ Fetch a string argument into a buffer; absent or non-string yields empty. }
PROCEDURE ArgBuf(job: ADRMEM; key: ByteStr; VAR out: ByteBuf);
VAR
  ignored: BOOLEAN;
BEGIN
  BufClear(out);
  ignored := JxGetStrToBuf(job, key, out);
END;

FUNCTION RunJob(job: ADRMEM): ADRMEM;
VAR
  op: ByteStr;
  res: ADRMEM;
  a, b, c, out: ByteBuf;
  req: PxRequest;
  reply: PxReply;
  outcome: INTEGER32;
BEGIN
  JxGetStr(job, 'op', op);
  res := JxNewObject;
  BufInit(a, 0);
  BufInit(b, 0);
  BufInit(c, 0);
  BufInit(out, 0);

  IF op = 'compute_prefix' THEN
  BEGIN
    ArgBuf(job, 'buffer', a);
    PxComputePrefix(a, JxGetInt(job, 'line'), JxGetInt(job, 'column'), out);
    JxAddStrFromBuf(res, 'prefix', out);
  END
  ELSE IF op = 'build_prompt' THEN
  BEGIN
    ArgBuf(job, 'goal', a);
    ArgBuf(job, 'prefix', b);
    ArgBuf(job, 'grammar', c);
    PxBuildPrompt(a, b, c, out);
    JxAddStrFromBuf(res, 'prompt', out);
  END
  ELSE IF op = 'system_prompt' THEN
  BEGIN
    PxSystemPrompt(out);
    JxAddStrFromBuf(res, 'text', out);
  END
  ELSE IF op = 'validate_request' THEN
  BEGIN
    PxRequestInit(req);
    IF PxValidateRequest(JxGet(job, 'payload'), JxGetInt(job, 'buffer_limit'),
                         req) THEN
    BEGIN
      JxAddStr(res, 'ok', 'yes');
      JxAddStrFromBuf(res, 'goal', req.goal);
      JxAddStrFromBuf(res, 'buffer', req.buffer);
      JxAddInt(res, 'line', req.line);
      JxAddInt(res, 'column', req.column);
    END
    ELSE
    BEGIN
      JxAddStr(res, 'ok', 'no');
      JxAddStr(res, 'error', req.error);
    END;
    PxRequestFree(req);
  END
  ELSE IF op = 'strip_code_fence' THEN
  BEGIN
    ArgBuf(job, 'text', a);
    PxStripCodeFence(a, out);
    JxAddStrFromBuf(res, 'text', out);
  END
  ELSE IF op = 'sanitize' THEN
  BEGIN
    ArgBuf(job, 'text', a);
    PxSanitizeCompletion(a, JxGetInt(job, 'max_lines'), out);
    JxAddStrFromBuf(res, 'text', out);
  END
  ELSE IF op = 'extract_completion' THEN
  BEGIN
    PxReplyInit(reply);
    outcome := PxExtractCompletion(JxGet(job, 'response'), reply);
    JxAddInt(res, 'outcome', outcome);
    IF outcome = PX_UP_OK THEN
    BEGIN
      JxAddStrFromBuf(res, 'text', reply.text);
      JxAddStrFromBuf(res, 'model', reply.model);
      JxAddStrFromBuf(res, 'request_id', reply.request_id);
    END
    ELSE
      JxAddStr(res, 'error', reply.error);
    PxReplyFree(reply);
  END
  ELSE
    JxAddStr(res, 'error', 'unknown op');

  BufFree(a);
  BufFree(b);
  BufFree(c);
  BufFree(out);
  RunJob := res;
END;

BEGIN
  BufInit(input_buf, 0);
  ReadAll(input_buf);
  jobs := JxParseBuf(input_buf);
  IF NOT JxIsArray(jobs) THEN
  BEGIN
    WRITELN('transforms: stdin was not a JSON array of jobs');
    exit(1);
  END;

  results := JxNewArray;
  n := JxArrSize(jobs);
  FOR i := 0 TO n - 1 DO
  BEGIN
    job := JxArrItem(jobs, i);
    result_obj := RunJob(job);
    JxArrAppend(results, result_obj);
  END;

  BufInit(out_buf, 0);
  IF NOT JxPrintToBuf(results, out_buf) THEN
    WRITELN('transforms: could not serialize the results')
  ELSE
  BEGIN
    FOR i := 0 TO BufLen(out_buf) - 1 DO
      WRITE(BufAt(out_buf, i));
    WRITELN;
  END;
END.
