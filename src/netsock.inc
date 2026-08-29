{ INTERFACE header for netsock, TCP sockets for programs in this dialect.

  The C side (runtime/netsock.c) holds everything the dialect cannot express:
  struct sockaddr layout, network byte order, getaddrinfo's linked list, and
  the errno retry dances. What crosses the boundary is only descriptors, byte
  buffers with explicit lengths, and small integers.

  Call NetInit once at startup, before any other routine here: it ignores
  SIGPIPE, so a client vanishing mid-response turns the next write into a
  reportable error instead of killing the process outright.

  A forking server should also call NetAutoReapChildren, which stops exited
  children becoming zombies. That is deliberately a second call rather than
  part of NetInit, because it has a visible cost: once children are reaped
  automatically, NetWaitChild can no longer find one and returns -1. A program
  that wants child exit statuses calls only NetInit.

  Lengths are INTEGER32 throughout. A response body routinely exceeds 32767
  bytes, and a bare INTEGER would silently wrap; remember also that an integer
  literal above 32767 wraps where it is written, so sizes must be computed
  rather than spelled out (see bytebuf.inc).

  Requires bytebuf, whose ByteBuf carries received data and whose ByteStr is
  reused here rather than declaring another LSTRING(255) alias. }

INTERFACE;
UNIT netsock (NetInit, NetAutoReapChildren, NetListen, NetPort, NetAccept, NetConnect,
              NetRead, NetWrite, NetWriteStr, NetShutdownWrite, NetClose,
              NetUrlSplit,
              NetForkChild, NetWaitChild, NetExit, NetChunkSize);

USES bytebuf;

CONST
  { Outcomes from NetRead that are not byte counts. A caller implementing a
    request timeout must distinguish "the deadline passed" from "the peer
    closed the connection"; collapsing them makes a stalled backend
    indistinguishable from a finished response. }
  NET_ERROR   = -1;
  NET_TIMEOUT = -2;

{ Startup. Safe to call more than once. See the SIGCHLD caveat above: this is
  the right call for a server that forks and never collects exit statuses, and
  the wrong one for a program that waits on specific children. }
PROCEDURE NetInit;
PROCEDURE NetAutoReapChildren;

{ Listening. A port of 0 asks the kernel to choose a free one, which NetPort
  then reports -- how a test listens without hard-coding a port that may
  already be in use. NetListen returns a descriptor, or a negative value on
  failure. A backlog of 0 selects a sensible default. }
FUNCTION NetListen(host: ByteStr; port: INTEGER32;
                   backlog: INTEGER32): INTEGER32;
FUNCTION NetPort(fd: INTEGER32): INTEGER32;
FUNCTION NetAccept(listen_fd: INTEGER32): INTEGER32;

{ Connecting. A positive timeout_ms also bounds every later read and write on
  the returned descriptor, so a backend that accepts and then stalls cannot
  hang the caller indefinitely. }
FUNCTION NetConnect(host: ByteStr; port: INTEGER32;
                    timeout_ms: INTEGER32): INTEGER32;

{ Transfer. NetRead appends what it receives to `into` and returns the number
  of bytes appended, 0 at end of stream, or NET_ERROR / NET_TIMEOUT. NetWrite
  sends a whole buffer, returning the count or NET_ERROR: it loops internally,
  because a short write is ordinary on a socket and treating one write as
  complete would silently truncate responses under load. }
FUNCTION NetRead(fd: INTEGER32; VAR into: ByteBuf;
                 timeout_ms: INTEGER32): INTEGER32;
FUNCTION NetWrite(fd: INTEGER32; VAR from: ByteBuf): INTEGER32;
FUNCTION NetWriteStr(fd: INTEGER32; s: ByteStr): INTEGER32;

{ Half-close: the peer sees end-of-input while this end can still read the
  reply. Without it, an exchange where both sides write before either reads
  can deadlock once the socket buffers fill. }
PROCEDURE NetShutdownWrite(fd: INTEGER32);
PROCEDURE NetClose(fd: INTEGER32);

{ Split "http://host[:port][/path]". Returns FALSE for anything else,
  including an https URL: there is no TLS here, and quietly connecting in the
  clear to a URL that asked for encryption would be worse than refusing. }
FUNCTION NetUrlSplit(url: ADRMEM; VAR host: ByteStr; VAR port: INTEGER32;
                     VAR path: ByteStr): BOOLEAN;

{ Process control, exposed here so a forking server need not redeclare the
  POSIX externs itself. NetForkChild returns 0 in the child and the child's
  pid in the parent, or a negative value on failure. }
FUNCTION NetForkChild: INTEGER32;
FUNCTION NetWaitChild(pid: INTEGER32): INTEGER32;
PROCEDURE NetExit(status: INTEGER32);

{ The read chunk size, exposed so a caller can size its own expectations. }
FUNCTION NetChunkSize: INTEGER32;

END;
