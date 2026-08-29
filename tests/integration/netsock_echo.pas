(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'netsock.inc'*)
PROGRAM netsock_echo(input, output);
{ End-to-end proof of the socket layer: a parent listens, a forked child
  connects and sends, the parent echoes it back, and the child checks what
  came home. This is the shape the completion proxy's accept loop will take.

  Only the parent writes to stdout. If both processes printed, the order of
  their lines would depend on scheduling and the expected-output file could
  not be stable.

  The payload deliberately exceeds both the 16-bit integer range and the
  socket buffer, so the transfer cannot complete in a single read or a single
  write. That is what makes the chunking loops meaningful: a version that
  assumed one read per message would pass a "hello" test and fail here.

  The child half-closes after sending. Without that the exchange can deadlock:
  the parent reads to end-of-input before replying, so if the child never
  signalled that it had finished, both ends would sit waiting for the other. }
USES bytebuf, netsock;

VAR
  listen_fd, conn_fd, client_fd, port, pid, n, i, payload_len: INTEGER32;
  received, payload, echoed, url: ByteBuf;
  split_host, split_path: ByteStr;
  split_port: INTEGER32;
  status, mismatches: INTEGER32;
  ok: BOOLEAN;

BEGIN
  NetInit;

  listen_fd := NetListen('127.0.0.1', 0, 16);
  IF listen_fd < 0 THEN
  BEGIN
    WRITELN('listen failed');
    NetExit(1);
  END;
  port := NetPort(listen_fd);
  IF port <= 0 THEN
  BEGIN
    WRITELN('port lookup failed');
    NetExit(1);
  END;

  { A payload of 100000 bytes: past both the 16-bit range and the socket's
    own 4096-byte chunk, so it takes several reads to arrive. }
  payload_len := 100000;
  BufInit(payload, 0);
  i := 0;
  WHILE i < payload_len DO
  BEGIN
    BufAppendChar(payload, CHR(65 + RETYPE(INTEGER, i MOD 26)));
    i := i + 1;
  END;

  pid := NetForkChild;
  IF pid = 0 THEN
  BEGIN
    { Child: connect, send everything, half-close, read the echo back. }
    NetClose(listen_fd);
    client_fd := NetConnect('127.0.0.1', port, 5000);
    IF client_fd < 0 THEN NetExit(2);
    IF NetWrite(client_fd, payload) <> payload_len THEN NetExit(3);
    NetShutdownWrite(client_fd);

    BufInit(echoed, 0);
    n := NetRead(client_fd, echoed, 5000);
    WHILE n > 0 DO
      n := NetRead(client_fd, echoed, 5000);
    NetClose(client_fd);

    IF n < 0 THEN NetExit(4);
    IF BufLen(echoed) <> payload_len THEN NetExit(5);
    mismatches := 0;
    i := 0;
    WHILE i < payload_len DO
    BEGIN
      IF BufAt(echoed, i) <> BufAt(payload, i) THEN
        mismatches := mismatches + 1;
      i := i + 1;
    END;
    IF mismatches <> 0 THEN NetExit(6);
    NetExit(0);
  END;

  { Parent: accept one connection, read to end of input, echo it back. }
  conn_fd := NetAccept(listen_fd);
  IF conn_fd < 0 THEN
  BEGIN
    WRITELN('accept failed');
    NetExit(1);
  END;

  BufInit(received, 0);
  n := NetRead(conn_fd, received, 5000);
  WHILE n > 0 DO
    n := NetRead(conn_fd, received, 5000);

  WRITELN('read-outcome=', n);
  WRITELN('received=', BufLen(received));
  WRITELN('matches=', BufLen(received) = payload_len);

  ok := NetWrite(conn_fd, received) = BufLen(received);
  WRITELN('echoed-all=', ok);
  NetClose(conn_fd);
  NetClose(listen_fd);

  status := NetWaitChild(pid);
  WRITELN('child-status=', status);

  { URL splitting, which the upstream client will lean on. }
  BufInit(url, 0);
  BufAppendStr(url, 'http://127.0.0.1:8080/v1');
  WRITELN('split=', NetUrlSplit(BufCStr(url), split_host, split_port,
                                split_path));
  WRITELN('  host=', split_host, ' port=', split_port, ' path=', split_path);

  BufClear(url);
  BufAppendStr(url, 'http://example.invalid/v1/chat');
  WRITELN('default-port=', NetUrlSplit(BufCStr(url), split_host, split_port,
                                       split_path));
  WRITELN('  host=', split_host, ' port=', split_port, ' path=', split_path);

  { https is refused rather than silently connecting in the clear. }
  BufClear(url);
  BufAppendStr(url, 'https://example.invalid/v1');
  WRITELN('https-refused=', NOT NetUrlSplit(BufCStr(url), split_host,
                                            split_port, split_path));
END.
