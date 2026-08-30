(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'netsock.inc'*)
(*$INCLUDE:'sysutil.inc'*)
PROGRAM conformance_raw(input, output);
{ Send one request exactly as stored on disk, then write the raw response.
  This is deliberately below HTTP parsing: conformance cases include malformed
  request bodies and headers which an HTTP client must not "fix". }
USES bytebuf, argparse, netsock, sysutil;

PROCEDURE WriteBuf(VAR b: ByteBuf);
VAR i, n: INTEGER32;
BEGIN
  n := BufLen(b);
  FOR i := 0 TO n - 1 DO WRITE(BufAt(b, i));
END;

VAR
  host, short_arg: ByteStr;
  arg: ArgStr;
  request_path, request, response: ByteBuf;
  fd, port, timeout_ms, rc: INTEGER32;

PROCEDURE ToByteStr(src: ArgStr; VAR dst: ByteStr);
VAR i, n: INTEGER;
BEGIN
  n := ORD(src[0]);
  dst[0] := CHR(n);
  FOR i := 1 TO n DO dst[i] := src[i];
END;

BEGIN
  ArgBegin('conformance_raw', 'Send raw request bytes to a proxy.');
  ArgString('host', ARG_NO_SHORT, '127.0.0.1', 'proxy host');
  ArgInt('port', ARG_NO_SHORT, 8790, 'proxy port');
  ArgString('request', 'r', '', 'file containing raw request bytes');
  ArgInt('timeout', 't', 30, 'connect and read timeout in seconds');
  IF NOT ArgParse THEN BEGIN ArgUsage; NetExit(2); END;
  IF ArgHelpWanted THEN BEGIN ArgUsage; NetExit(0); END;
  ArgGetStr('host', arg); ToByteStr(arg, host);
  ArgGetStr('request', arg); ToByteStr(arg, short_arg);
  BufInit(request_path, 0); BufAppendStr(request_path, short_arg);
  IF BufLen(request_path) = 0 THEN BEGIN
    WRITELN('conformance_raw: --request is required'); NetExit(2);
  END;

  BufInit(request, 0); BufInit(response, 0);
  IF NOT SysReadFile(request_path, request) THEN BEGIN
    WRITELN('conformance_raw: cannot read request file'); NetExit(1);
  END;
  port := ArgGetInt('port'); timeout_ms := ArgGetInt('timeout') * 1000;
  NetInit;
  fd := NetConnect(host, port, timeout_ms);
  IF fd < 0 THEN BEGIN
    WRITELN('conformance_raw: cannot connect to ', host, ' port ', port);
    NetExit(1);
  END;
  rc := NetWrite(fd, request);
  IF rc <> BufLen(request) THEN BEGIN
    NetClose(fd); WRITELN('conformance_raw: request write failed'); NetExit(1);
  END;
  NetShutdownWrite(fd);
  rc := NetRead(fd, response, timeout_ms);
  WHILE rc > 0 DO rc := NetRead(fd, response, timeout_ms);
  NetClose(fd);
  IF rc = NET_TIMEOUT THEN BEGIN
    BufAppendStr(response, '<<READ TIMED OUT>>');
  END ELSE IF rc = NET_ERROR THEN BEGIN
    WRITELN('conformance_raw: response read failed'); NetExit(1);
  END;
  WriteBuf(response);
  BufFree(request_path); BufFree(request); BufFree(response);
END.
