(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'httpio.inc'*)
(*$INCLUDE:'sysutil.inc'*)
PROGRAM conformance_runner(input, output);
{ Replay the language-neutral raw-request fixture corpus.  Process startup and
  stub lifecycle remain deliberately outside this program. }
USES bytebuf, argparse, netsock, jsonx, httpio, sysutil;

PROCEDURE ToByteStr(src: ArgStr; VAR dst: ByteStr);
VAR i, n: INTEGER;
BEGIN n := ORD(src[0]); dst[0] := CHR(n); FOR i := 1 TO n DO dst[i] := src[i]; END;

FUNCTION HexValue(c: CHAR): INTEGER32;
BEGIN
  IF (c >= '0') AND (c <= '9') THEN HexValue := ORD(c) - ORD('0')
  ELSE IF (c >= 'a') AND (c <= 'f') THEN HexValue := ORD(c) - ORD('a') + 10
  ELSE IF (c >= 'A') AND (c <= 'F') THEN HexValue := ORD(c) - ORD('A') + 10
  ELSE HexValue := -1;
END;

FUNCTION HexToBuf(VAR text: ByteBuf; VAR out: ByteBuf): BOOLEAN;
VAR i, a, b: INTEGER32;
BEGIN
  HexToBuf := FALSE; BufClear(out);
  IF (BufLen(text) MOD 2) <> 0 THEN RETURN;
  i := 0;
  WHILE i < BufLen(text) DO BEGIN
    a := HexValue(BufAt(text, i)); b := HexValue(BufAt(text, i + 1));
    IF (a < 0) OR (b < 0) THEN RETURN;
    BufAppendChar(out, CHR(a * 16 + b)); i := i + 2;
  END;
  HexToBuf := TRUE;
END;

PROCEDURE NormalizeBody(VAR body: ByteBuf; upstream_url: ByteStr; VAR out: ByteBuf);
VAR i: INTEGER32;
BEGIN
  i := 0;
  WHILE i < BufLen(body) DO BEGIN
    IF (ORD(upstream_url[0]) > 0) AND BufMatchesStrAt(body, i, upstream_url) THEN BEGIN
      BufAppendStr(out, '<UPSTREAM>'); i := i + ORD(upstream_url[0]);
    END ELSE BEGIN BufAppendChar(out, BufAt(body, i)); i := i + 1; END;
  END;
END;

PROCEDURE AddResponse(VAR entry: ADRMEM; host, upstream_url: ByteStr; port, timeout_ms: INTEGER32;
                      VAR request: ByteBuf);
VAR fd, rc: INTEGER32; raw, body, normalized: ByteBuf; resp: HttpResp; content_type: ByteStr;
    parsed: ADRMEM;
BEGIN
  fd := NetConnect(host, port, timeout_ms);
  IF fd < 0 THEN BEGIN JxAddStr(entry, 'error', 'connect failed'); RETURN; END;
  BufInit(raw, 0);
  rc := NetWrite(fd, request);
  IF rc = BufLen(request) THEN NetShutdownWrite(fd);
  IF rc = BufLen(request) THEN rc := HttpReadRespHead(fd, raw, resp, 65000, timeout_ms);
  IF rc = HTTP_HEAD_OK THEN BEGIN
    IF resp.content_length >= 0 THEN BEGIN
      IF NOT HttpReadRespBody(fd, raw, resp, resp.content_length, timeout_ms) THEN rc := HTTP_HEAD_EOF;
    END;
  END;
  NetClose(fd);
  IF rc <> HTTP_HEAD_OK THEN BEGIN JxAddStr(entry, 'error', 'no response'); BufFree(raw); RETURN; END;
  JxAddInt(entry, 'status', resp.status);
  content_type := '';
  IF HttpRespHeaderValue(raw, resp, 'Content-Type', content_type) THEN JxAddStr(entry, 'content_type', content_type)
  ELSE JxAddItem(entry, 'content_type', JxNewStr(''));
  BufInit(body, 0); BufInit(normalized, 0); HttpRespBodyToBuf(raw, resp, body);
  NormalizeBody(body, upstream_url, normalized); parsed := JxParseBuf(normalized);
  IF parsed <> NIL THEN JxAddItem(entry, 'body', parsed)
  ELSE JxAddStrFromBuf(entry, 'body_raw', normalized);
  BufFree(normalized); BufFree(body); BufFree(raw);
END;

PROCEDURE AddUpstreamRequest(VAR entry: ADRMEM; host: ByteStr; port, timeout_ms: INTEGER32);
VAR request, raw, body: ByteBuf; fd, rc: INTEGER32; resp: HttpResp; parsed: ADRMEM;
BEGIN
  BufInit(request, 0); BufInit(raw, 0); BufInit(body, 0);
  HttpAppendRequestLine(request, 'GET', '/_last'); HttpAppendHeader(request, 'Host', 'xx');
  HttpAppendHeader(request, 'Connection', 'close'); HttpEndHeaders(request);
  fd := NetConnect(host, port, timeout_ms);
  IF fd >= 0 THEN BEGIN
    rc := NetWrite(fd, request); IF rc = BufLen(request) THEN NetShutdownWrite(fd);
    IF rc = BufLen(request) THEN rc := HttpReadRespHead(fd, raw, resp, 65000, timeout_ms);
    IF (rc = HTTP_HEAD_OK) AND (resp.content_length >= 0) THEN
      IF NOT HttpReadRespBody(fd, raw, resp, resp.content_length, timeout_ms) THEN rc := HTTP_HEAD_EOF;
    NetClose(fd);
    IF rc = HTTP_HEAD_OK THEN BEGIN
      HttpRespBodyToBuf(raw, resp, body); parsed := JxParseBuf(body);
      IF parsed <> NIL THEN JxAddItem(entry, 'upstream_request', parsed);
    END;
  END;
  BufFree(body); BufFree(raw); BufFree(request);
END;

FUNCTION FindGolden(cases: ADRMEM; name: ByteStr): ADRMEM;
VAR i, n: INTEGER32; item: ADRMEM; found: ByteStr;
BEGIN
  FindGolden := NIL; n := JxArrSize(cases); i := 0;
  WHILE i < n DO BEGIN
    item := JxArrItem(cases, i); JxGetStr(item, 'name', found);
    IF found = name THEN BEGIN FindGolden := item; RETURN; END;
    i := i + 1;
  END;
END;

PROCEDURE WriteBuf(VAR b: ByteBuf);
VAR i: INTEGER32;
BEGIN FOR i := 0 TO BufLen(b) - 1 DO WRITE(BufAt(b, i)); END;

VAR host, fixture_short, upstream_url: ByteStr; arg: ArgStr; fixture, golden_file, text, request, rendered: ByteBuf;
    root, cases, golden_root, golden_cases, item, expected, report, output, entry: ADRMEM;
    port, stub_port, timeout_ms, i, n: INTEGER32;
    all_match: BOOLEAN;
BEGIN
  ArgBegin('conformance_runner', 'Replay proxy conformance fixture requests.');
  ArgString('host', ARG_NO_SHORT, '127.0.0.1', 'proxy host');
  ArgInt('port', ARG_NO_SHORT, 8790, 'proxy port');
  ArgInt('stub-port', ARG_NO_SHORT, 0, 'stub upstream port for /_last checks');
  ArgString('upstream-url', ARG_NO_SHORT, '', 'URL to mask in response JSON');
  ArgString('golden', ARG_NO_SHORT, '', 'golden report to compare fixture cases against');
  ArgString('fixtures', ARG_NO_SHORT, 'tests/proxy/conformance_cases.json', 'fixture JSON file');
  ArgInt('timeout', 't', 30, 'request timeout in seconds');
  IF NOT ArgParse THEN BEGIN ArgUsage; NetExit(2); END;
  IF ArgHelpWanted THEN BEGIN ArgUsage; NetExit(0); END;
  ArgGetStr('host', arg); ToByteStr(arg, host);
  ArgGetStr('fixtures', arg); ToByteStr(arg, fixture_short);
  ArgGetStr('upstream-url', arg); ToByteStr(arg, upstream_url);
  BufInit(fixture, 0); BufAppendStr(fixture, fixture_short); BufInit(golden_file, 0); BufInit(text, 0); BufInit(request, 0);
  ArgGetStr('golden', arg); ToByteStr(arg, fixture_short); BufAppendStr(golden_file, fixture_short);
  golden_root := NIL; golden_cases := NIL;
  IF BufLen(golden_file) > 0 THEN BEGIN
    BufInit(rendered, 0);
    IF NOT SysReadFile(golden_file, rendered) THEN BEGIN WRITELN('conformance_runner: cannot read golden'); NetExit(1); END;
    golden_root := JxParseBuf(rendered); golden_cases := JxGet(golden_root, 'cases'); BufFree(rendered);
    IF NOT JxIsArray(golden_cases) THEN BEGIN WRITELN('conformance_runner: invalid golden'); NetExit(1); END;
  END;
  IF NOT SysReadFile(fixture, text) THEN BEGIN WRITELN('conformance_runner: cannot read fixtures'); NetExit(1); END;
  root := JxParseBuf(text); cases := JxGet(root, 'cases');
  IF NOT JxIsArray(cases) THEN BEGIN WRITELN('conformance_runner: invalid fixtures'); NetExit(1); END;
  port := ArgGetInt('port'); stub_port := ArgGetInt('stub-port'); timeout_ms := ArgGetInt('timeout') * 1000; NetInit;
  report := JxNewObject; output := JxNewArray; JxAddItem(report, 'cases', output);
  all_match := TRUE; n := JxArrSize(cases);
  FOR i := 0 TO n - 1 DO BEGIN
    item := JxArrItem(cases, i); BufClear(text); JxGetStrToBuf(item, 'request_hex', text);
    entry := JxNewObject; JxGetStr(item, 'name', fixture_short); JxAddStr(entry, 'name', fixture_short);
    JxGetStr(item, 'note', fixture_short); JxAddStr(entry, 'note', fixture_short);
    IF HexToBuf(text, request) THEN BEGIN
      AddResponse(entry, host, upstream_url, port, timeout_ms, request);
      IF JxIsTrue(JxGet(item, 'capture_upstream')) AND (stub_port > 0) THEN
        AddUpstreamRequest(entry, host, stub_port, timeout_ms);
    END ELSE JxAddStr(entry, 'error', 'invalid request hex');
    IF golden_cases <> NIL THEN BEGIN
      JxGetStr(entry, 'name', fixture_short); expected := FindGolden(golden_cases, fixture_short);
      IF (expected = NIL) OR NOT JxEqual(entry, expected) THEN all_match := FALSE;
    END;
    JxArrAppend(output, entry);
  END;
  BufInit(rendered, 0); JxPrintToBuf(report, rendered); WriteBuf(rendered); WRITELN;
  BufFree(rendered); JxDelete(report); JxDelete(root); IF golden_root <> NIL THEN JxDelete(golden_root);
  BufFree(request); BufFree(text); BufFree(golden_file); BufFree(fixture);
  IF NOT all_match THEN NetExit(1);
END.
