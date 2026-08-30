{ INTERFACE header for sysutil, a small POSIX substrate for programs in this
  dialect.  It exposes only stable, reusable operations; test suites supply
  their own traversal policy, filtering, process arguments, and reporting.
  SysExec collects a child status itself, so do not combine it with
  NetAutoReapChildren from netsock.

  Paths and entry names use ByteBuf rather than LSTRING so an OS path is not
  silently truncated at 255 bytes.  Callers retain ownership of every buffer.

  SysExec never invokes a shell.  SysArgs holds pointers into caller-owned
  ByteBuf values, so do not append to an argument buffer after adding it and
  keep all argument buffers alive until SysExec returns. }

INTERFACE;
UNIT sysutil (SysDirOpen, SysDirNext, SysDirClose,
              SysTempDirCreate, SysRemoveTree, SysReadFile, SysWriteFile,
              SysArgsInit, SysArgsFree, SysArgsAdd, SysExec);

USES bytebuf;

CONST
  SYS_OK       = 0;
  SYS_ERROR    = -1;
  SYS_TIMEOUT  = -2;
  SYS_SIGNAL   = -3;

  SYS_ENTRY_OTHER = 0;
  SYS_ENTRY_DIR   = 1;
  SYS_ENTRY_FILE  = 2;

  SYS_DIR_ENTRY = 1;  { SysDirNext result: entry available }
  SYS_DIR_END   = 0;  { SysDirNext result: end-of-directory }

  SYS_MAX_ARGS = 15;

TYPE
  SysDir = RECORD
    handle: ADRMEM;
  END;
  SysArgs = RECORD
    count: INTEGER32;
    payload: ByteBuf;
  END;

{ Directory iteration is deliberately shallow.  SysDirNext returns
  SYS_DIR_ENTRY, SYS_DIR_END, or SYS_ERROR. }
FUNCTION SysDirOpen(VAR path: ByteBuf; VAR dir: SysDir): BOOLEAN;
FUNCTION SysDirNext(VAR dir: SysDir; VAR name: ByteBuf;
                    VAR kind: INTEGER32): INTEGER32;
FUNCTION SysDirClose(VAR dir: SysDir): BOOLEAN;

{ The caller owns a directory returned by SysTempDirCreate and must call
  SysRemoveTree after use.  Cleanup does not follow symlinks. }
FUNCTION SysTempDirCreate(VAR prefix: ByteBuf; VAR path: ByteBuf): BOOLEAN;
FUNCTION SysRemoveTree(VAR path: ByteBuf): BOOLEAN;

{ File contents are binary-safe and may contain NUL bytes.  SysReadFile clears
  contents before reading.  SysWriteFile truncates or creates a file with mode
  0600. }
FUNCTION SysReadFile(VAR path: ByteBuf; VAR contents: ByteBuf): BOOLEAN;
FUNCTION SysWriteFile(VAR path: ByteBuf; VAR contents: ByteBuf): BOOLEAN;

{ SysArgs serializes arguments after argv[0] as NUL-terminated byte strings;
  SysExec supplies executable as argv[0].  A normally-exited program, including
  one with a nonzero exit code, returns SYS_OK with exit_code set.
  timeout_ms is a millisecond bound: 0 waits indefinitely; a positive value
  kills the child process group after that many milliseconds and returns
  SYS_TIMEOUT; a negative value is rejected with SYS_ERROR. }
PROCEDURE SysArgsInit(VAR args: SysArgs);
PROCEDURE SysArgsFree(VAR args: SysArgs);
FUNCTION SysArgsAdd(VAR args: SysArgs; VAR arg: ByteBuf): BOOLEAN;
FUNCTION SysExec(VAR executable: ByteBuf; VAR args: SysArgs;
                 timeout_ms: INTEGER32; VAR exit_code: INTEGER32;
                 VAR term_signal: INTEGER32; VAR diagnostics: ByteBuf): INTEGER32;

END;
