(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'httpio.inc'*)
(*$INCLUDE:'sysutil.inc'*)
PROGRAM corpus_smoke(input, output);

USES bytebuf, argparse, netsock, jsonx, httpio, sysutil;

TYPE
  CorpusNames = ARRAY [0..127] OF ByteStr;

FUNCTION StrLess(VAR a, b: ByteStr): BOOLEAN;
VAR i, limit: INTEGER32;
BEGIN
  limit := ORD(a[0]);
  IF ORD(b[0]) < limit THEN limit := ORD(b[0]);
  i := 1;
  WHILE (i <= limit) AND (a[i] = b[i]) DO i := i + 1;
  IF i > limit THEN StrLess := ORD(a[0]) < ORD(b[0])
  ELSE StrLess := ORD(a[i]) < ORD(b[i]);
END;

FUNCTION IsJsonName(VAR name: ByteBuf): BOOLEAN;
VAR n: INTEGER32;
BEGIN
  n := BufLen(name);
  IsJsonName := (n >= 6) AND BufMatchesStrAt(name, n - 5, '.json');
END;

PROCEDURE WriteBuf(VAR b: ByteBuf; limit: INTEGER32);
VAR i, n: INTEGER32;
BEGIN
  n := BufLen(b);
  IF n > limit THEN n := limit;
  FOR i := 0 TO n - 1 DO WRITE(BufAt(b, i));
END;

VAR
  corpus_dir, host_buf, path, name, source, payload_buf, request, raw, body,
  completion, compiler, temp_dir, candidate, prefix, diagnostics: ByteBuf;
  host: ByteStr;
  dir: SysDir;
  resp: HttpResp;
  root, item, cursor, payload, response_tree, completions: ADRMEM;
  names: CorpusNames;
  args: SysArgs;
  kind, next, name_count, i, j, limit, timeout_ms, port, fd, rc, failures,
  empty, built, eligible, result, exit_code, term_signal: INTEGER32;
  swapped, id: ByteStr;
  check_compiles, cleanup_ok: BOOLEAN;

BEGIN
  ArgBegin('corpus_smoke', 'Replay completion corpus through a running proxy.');
  ArgString('host', ARG_NO_SHORT, '127.0.0.1', 'proxy host');
  ArgInt('port', ARG_NO_SHORT, 8790, 'proxy port');
  ArgString('corpus', ARG_NO_SHORT, 'tests/proxy/corpus', 'corpus directory');
  ArgString('compiler', ARG_NO_SHORT, '', 'compiler for completion checks');
  ArgInt('limit', ARG_NO_SHORT, 0, 'maximum corpus items (zero means all)');
  ArgInt('timeout', 't', 60, 'request and compiler timeout in seconds');
  IF NOT ArgParse THEN BEGIN ArgUsage; NetExit(2); END;
  IF ArgHelpWanted THEN BEGIN ArgUsage; NetExit(0); END;

  BufInit(corpus_dir, 0); BufInit(host_buf, 0); BufInit(path, 0);
  BufInit(name, 0); BufInit(source, 0); BufInit(payload_buf, 0);
  BufInit(request, 0); BufInit(raw, 0); BufInit(body, 0); BufInit(completion, 0);
  BufInit(compiler, 0); BufInit(temp_dir, 0); BufInit(candidate, 0);
  BufInit(prefix, 0); BufInit(diagnostics, 0);
  BufAppendCStr(corpus_dir, ArgGetRaw('corpus'));
  BufAppendCStr(host_buf, ArgGetRaw('host'));
  BufAppendCStr(compiler, ArgGetRaw('compiler'));
  BufSliceToStr(host_buf, 0, BufLen(host_buf), host);
  port := ArgGetInt('port'); limit := ArgGetInt('limit');
  timeout_ms := ArgGetInt('timeout') * 1000;
  check_compiles := BufLen(compiler) > 0;
  IF check_compiles THEN
  BEGIN
    BufAppendStr(prefix, 'pascal-smoke-');
    IF NOT SysTempDirCreate(prefix, temp_dir) THEN BEGIN WRITELN('could not create temporary directory'); NetExit(1); END;
    BufAppendBuf(candidate, temp_dir); BufAppendStr(candidate, '/candidate.pas');
  END;

  name_count := 0;
  IF NOT SysDirOpen(corpus_dir, dir) THEN BEGIN WRITELN('could not open corpus directory'); NetExit(1); END;
  next := SysDirNext(dir, name, kind);
  WHILE next = SYS_DIR_ENTRY DO
  BEGIN
    IF (kind = SYS_ENTRY_FILE) AND IsJsonName(name) AND (name_count < 128) THEN
    BEGIN BufSliceToStr(name, 0, BufLen(name), names[name_count]); name_count := name_count + 1; END;
    next := SysDirNext(dir, name, kind);
  END;
  SysDirClose(dir);
  FOR i := 1 TO name_count - 1 DO BEGIN
    j := i;
    WHILE (j > 0) AND StrLess(names[j], names[j - 1]) DO BEGIN swapped := names[j]; names[j] := names[j - 1]; names[j - 1] := swapped; j := j - 1; END;
  END;
  IF (limit > 0) AND (limit < name_count) THEN name_count := limit;

  NetInit; failures := 0; empty := 0; built := 0; eligible := 0;
  FOR i := 0 TO name_count - 1 DO
  BEGIN
    BufClear(name); BufAppendStr(name, names[i]); BufClear(path);
    BufAppendBuf(path, corpus_dir); BufAppendChar(path, '/'); BufAppendBuf(path, name);
    IF NOT SysReadFile(path, source) THEN BEGIN failures := failures + 1; WRITELN('FAIL unreadable ', names[i]); END
    ELSE BEGIN
      root := JxParseBuf(source);
      IF root = NIL THEN BEGIN failures := failures + 1; WRITELN('FAIL invalid JSON ', names[i]); END
      ELSE BEGIN
        BufClear(payload_buf);
        item := root; cursor := JxGet(item, 'cursor'); payload := JxNewObject;
        JxGetStrToBuf(item, 'goal', payload_buf); JxAddStrFromBuf(payload, 'goal', payload_buf); BufClear(payload_buf);
        JxGetStrToBuf(item, 'buffer', payload_buf); JxAddStrFromBuf(payload, 'buffer', payload_buf); BufClear(payload_buf);
        response_tree := JxNewObject;
        JxAddInt(response_tree, 'line', JxGetInt(cursor, 'line'));
        JxAddInt(response_tree, 'column', JxGetInt(cursor, 'column'));
        JxAddItem(payload, 'cursor', response_tree);
        JxPrintToBuf(payload, payload_buf); JxDelete(payload);
        BufClear(request); HttpAppendRequestLine(request, 'POST', '/complete');
        HttpAppendHeader(request, 'Host', host); HttpAppendHeader(request, 'Content-Type', 'application/json');
        HttpAppendHeaderInt(request, 'Content-Length', BufLen(payload_buf)); HttpEndHeaders(request); BufAppendBuf(request, payload_buf);
        fd := NetConnect(host, port, timeout_ms); rc := -1;
        IF fd >= 0 THEN BEGIN BufClear(raw); rc := HttpExchange(fd, request, raw, resp, 65000, timeout_ms); NetClose(fd); END;
        IF rc <> HTTP_HEAD_OK THEN BEGIN failures := failures + 1; WRITE('FAIL ', names[i], ' request'); WRITELN; END
        ELSE BEGIN
          BufClear(body); HttpRespBodyToBuf(raw, resp, body); response_tree := JxParseBuf(body);
          completions := NIL;
          IF response_tree <> NIL THEN completions := JxGet(response_tree, 'completions');
          IF (resp.status <> 200) OR NOT JxIsArray(completions) THEN BEGIN
            failures := failures + 1; WRITE('FAIL ', names[i], ' status=', resp.status, ' '); WriteBuf(body, 120); WRITELN;
          END ELSE IF JxArrSize(completions) = 0 THEN BEGIN empty := empty + 1; WRITELN('EMPTY ', names[i]); END
          ELSE BEGIN
            BufClear(completion); JxStrToBuf(JxArrItem(completions, 0), completion);
            JxGetStr(item, 'id', id); WRITE('ok   ', id, ' ', BufLen(completion), ' chars');
            IF check_compiles AND JxIsTrue(JxGet(item, 'compiles_when_appended')) THEN BEGIN
              eligible := eligible + 1; BufClear(source); JxGetStrToBuf(item, 'buffer', source); BufAppendBuf(source, completion);
              IF SysWriteFile(candidate, source) THEN BEGIN SysArgsInit(args); SysArgsAdd(args, candidate); result := SysExec(compiler, args, timeout_ms, exit_code, term_signal, diagnostics); SysArgsFree(args);
                IF (result = SYS_OK) AND (exit_code = 0) THEN BEGIN built := built + 1; WRITE(', compiles'); END ELSE WRITE(', does not compile');
              END ELSE WRITE(', cannot write candidate');
            END;
            WRITELN;
          END;
          IF response_tree <> NIL THEN JxDelete(response_tree);
        END;
        JxDelete(root);
      END;
    END;
  END;
  WRITELN; WRITELN(name_count, ' items: ', failures, ' protocol failures, ', empty, ' empty completions');
  IF eligible > 0 THEN WRITELN(built, ' of ', eligible, ' completions compiled when appended');
  cleanup_ok := TRUE; IF check_compiles THEN cleanup_ok := SysRemoveTree(temp_dir);
  IF (failures <> 0) OR NOT cleanup_ok THEN NetExit(1);
END.
