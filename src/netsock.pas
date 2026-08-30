{ IMPLEMENTATION of netsock. See netsock.inc for the contract, and
  runtime/netsock.c for the C side these routines are a thin skin over. }

(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'netsock.inc'*)

IMPLEMENTATION OF netsock;

FUNCTION pas_tcp_listen(host: ADRMEM; port: CINT; backlog: CINT): CINT [C]; EXTERN;
FUNCTION pas_tcp_port(fd: CINT): CINT [C]; EXTERN;
FUNCTION pas_tcp_accept(listen_fd: CINT): CINT [C]; EXTERN;
FUNCTION pas_tcp_connect(host: ADRMEM; port: CINT; timeout_ms: CINT): CINT [C]; EXTERN;
FUNCTION pas_sock_read(fd: CINT; buf: ADRMEM; cap: CLONG; timeout_ms: CINT): CLONG [C]; EXTERN;
FUNCTION pas_sock_write(fd: CINT; buf: ADRMEM; len: CLONG): CLONG [C]; EXTERN;
FUNCTION pas_url_split(url: ADRMEM; host: ADRMEM; hostcap: CINT; port: ADRMEM;
                       path: ADRMEM; pathcap: CINT): CINT [C]; EXTERN;
PROCEDURE pas_net_init [C]; EXTERN;
PROCEDURE pas_net_autoreap [C]; EXTERN;
PROCEDURE pas_sock_shutdown_write(fd: CINT) [C]; EXTERN;
PROCEDURE pas_sock_close(fd: CINT) [C]; EXTERN;
FUNCTION fork: CINT [C]; EXTERN;
FUNCTION waitpid(pid: CINT; status: ADRMEM; options: CINT): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

CONST
  NET_CHUNK = 4096;
  NET_HOSTCAP = 256;
  NET_PATHCAP = 1024;

TYPE
  NetChunk = ARRAY [0..4095] OF CHAR;
  NetHostBuf = ARRAY [0..255] OF CHAR;
  NetPathBuf = ARRAY [0..1023] OF CHAR;

{ ------------------------------------------------------------------ }
{ Startup                                                             }
{ ------------------------------------------------------------------ }

PROCEDURE NetInit;
BEGIN
  pas_net_init;
END;

PROCEDURE NetAutoReapChildren;
BEGIN
  pas_net_autoreap;
END;

FUNCTION NetChunkSize: INTEGER32;
BEGIN
  NetChunkSize := NET_CHUNK;
END;

{ ------------------------------------------------------------------ }
{ A NUL-terminated copy of a short string, for the C boundary          }
{ ------------------------------------------------------------------ }

PROCEDURE NetStrToBuf(s: ByteStr; VAR out: NetHostBuf);
VAR
  i, n: INTEGER32;
BEGIN
  n := ORD(s[0]);
  IF n > NET_HOSTCAP - 1 THEN n := NET_HOSTCAP - 1;
  i := 0;
  WHILE i < n DO
  BEGIN
    out[i] := s[i + 1];
    i := i + 1;
  END;
  out[n] := CHR(0);
END;

PROCEDURE NetCStrToStr(VAR src: NetHostBuf; VAR out: ByteStr);
VAR
  i, n: INTEGER32;
BEGIN
  n := 0;
  WHILE (n < NET_HOSTCAP) AND (src[n] <> CHR(0)) DO n := n + 1;
  IF n > 255 THEN n := 255;
  out[0] := CHR(RETYPE(INTEGER, n));
  i := 0;
  WHILE i < n DO
  BEGIN
    out[i + 1] := src[i];
    i := i + 1;
  END;
END;

PROCEDURE NetPathToStr(VAR src: NetPathBuf; VAR out: ByteStr);
VAR
  i, n: INTEGER32;
BEGIN
  n := 0;
  WHILE (n < NET_PATHCAP) AND (src[n] <> CHR(0)) DO n := n + 1;
  IF n > 255 THEN n := 255;
  out[0] := CHR(RETYPE(INTEGER, n));
  i := 0;
  WHILE i < n DO
  BEGIN
    out[i + 1] := src[i];
    i := i + 1;
  END;
END;

{ ------------------------------------------------------------------ }
{ Listening and connecting                                            }
{ ------------------------------------------------------------------ }

FUNCTION NetListen(host: ByteStr; port: INTEGER32;
                   backlog: INTEGER32): INTEGER32;
VAR
  hbuf: NetHostBuf;
BEGIN
  NetStrToBuf(host, hbuf);
  NetListen := pas_tcp_listen(ADR hbuf, RETYPE(CINT, port),
                              RETYPE(CINT, backlog));
END;

FUNCTION NetPort(fd: INTEGER32): INTEGER32;
BEGIN
  NetPort := pas_tcp_port(RETYPE(CINT, fd));
END;

FUNCTION NetAccept(listen_fd: INTEGER32): INTEGER32;
BEGIN
  NetAccept := pas_tcp_accept(RETYPE(CINT, listen_fd));
END;

FUNCTION NetConnect(host: ByteStr; port: INTEGER32;
                    timeout_ms: INTEGER32): INTEGER32;
VAR
  hbuf: NetHostBuf;
BEGIN
  NetStrToBuf(host, hbuf);
  NetConnect := pas_tcp_connect(ADR hbuf, RETYPE(CINT, port),
                                RETYPE(CINT, timeout_ms));
END;

{ ------------------------------------------------------------------ }
{ Transfer                                                            }
{ ------------------------------------------------------------------ }

FUNCTION NetRead(fd: INTEGER32; VAR into: ByteBuf;
                 timeout_ms: INTEGER32): INTEGER32;
VAR
  chunk: NetChunk;
  got: CLONG;
  n: INTEGER32;
BEGIN
  got := pas_sock_read(RETYPE(CINT, fd), ADR chunk, RETYPE(CLONG, NET_CHUNK),
                       RETYPE(CINT, timeout_ms));
  n := RETYPE(INTEGER32, got);
  IF n > 0 THEN BufAppendBytes(into, ADR chunk, n);
  NetRead := n;
END;

FUNCTION NetWrite(fd: INTEGER32; VAR from: ByteBuf): INTEGER32;
VAR
  sent: CLONG;
BEGIN
  IF BufLen(from) = 0 THEN
    NetWrite := 0
  ELSE
  BEGIN
    sent := pas_sock_write(RETYPE(CINT, fd), BufPtr(from),
                           RETYPE(CLONG, BufLen(from)));
    NetWrite := RETYPE(INTEGER32, sent);
  END;
END;

FUNCTION NetWriteStr(fd: INTEGER32; s: ByteStr): INTEGER32;
VAR
  tmp: ByteBuf;
  rc: INTEGER32;
BEGIN
  BufInit(tmp, 0);
  BufAppendStr(tmp, s);
  rc := NetWrite(fd, tmp);
  BufFree(tmp);
  NetWriteStr := rc;
END;

PROCEDURE NetShutdownWrite(fd: INTEGER32);
BEGIN
  pas_sock_shutdown_write(RETYPE(CINT, fd));
END;

PROCEDURE NetClose(fd: INTEGER32);
BEGIN
  pas_sock_close(RETYPE(CINT, fd));
END;

{ ------------------------------------------------------------------ }
{ URL splitting                                                       }
{ ------------------------------------------------------------------ }

FUNCTION NetUrlSplit(url: ADRMEM; VAR host: ByteStr; VAR port: INTEGER32;
                     VAR path: ByteStr): BOOLEAN;
VAR
  hbuf: NetHostBuf;
  pbuf: NetPathBuf;
  cport: CINT;
  rc: CINT;
BEGIN
  cport := 0;
  rc := pas_url_split(url, ADR hbuf, RETYPE(CINT, NET_HOSTCAP), ADR cport,
                      ADR pbuf, RETYPE(CINT, NET_PATHCAP));
  IF rc <> 0 THEN
    NetUrlSplit := FALSE
  ELSE
  BEGIN
    NetCStrToStr(hbuf, host);
    NetPathToStr(pbuf, path);
    port := cport;
    NetUrlSplit := TRUE;
  END;
END;

{ ------------------------------------------------------------------ }
{ Process control                                                     }
{ ------------------------------------------------------------------ }

FUNCTION NetForkChild: INTEGER32;
BEGIN
  NetForkChild := fork;
END;

{ The wait status packs the exit code in its upper byte, the vintage
  `status DIV 256` idiom. Returns a negative value if the child could not be
  waited for -- which is the normal outcome after NetInit, since ignoring
  SIGCHLD means children are reaped automatically and waitpid finds nothing. }
FUNCTION NetWaitChild(pid: INTEGER32): INTEGER32;
VAR
  status: CINT;
  rc: CINT;
BEGIN
  status := 0;
  rc := waitpid(RETYPE(CINT, pid), ADR status, 0);
  IF rc < 0 THEN
    NetWaitChild := -1
  ELSE
    NetWaitChild := RETYPE(INTEGER32, status) DIV 256;
END;

PROCEDURE NetExit(status: INTEGER32);
BEGIN
  exit(RETYPE(CINT, status));
END;

BEGIN
END.
