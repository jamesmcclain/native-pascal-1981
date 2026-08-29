{ IMPLEMENTATION of sysutil.  POSIX objects and process control remain on the
  C side; this layer converts them to ByteBuf and dialect-friendly records. }

(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'sysutil.inc'*)

IMPLEMENTATION OF sysutil;

FUNCTION pas_sys_dir_open(path: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION pas_sys_dir_next(handle: ADRMEM; name: ADRMEM; namecap: CINT): CINT [C]; EXTERN;
FUNCTION pas_sys_dir_close(handle: ADRMEM): CINT [C]; EXTERN;
FUNCTION pas_sys_temp_dir(prefix: ADRMEM; out: ADRMEM; outcap: CINT): CINT [C]; EXTERN;
FUNCTION pas_sys_remove_tree(path: ADRMEM): CINT [C]; EXTERN;
FUNCTION pas_sys_exec(executable: ADRMEM; packed_args: ADRMEM;
                      packed_args_len: CINT; timeout_ms: CINT;
                      exit_code: ADRMEM; term_signal: ADRMEM;
                      diagnostics: ADRMEM; diagnostics_cap: CINT;
                      diagnostics_len: ADRMEM): CINT [C]; EXTERN;

CONST
  SYS_PATH_CAP = 4096;
  SYS_DIAGNOSTIC_CAP = 8192;


FUNCTION SysDirOpen(VAR path: ByteBuf; VAR dir: SysDir): BOOLEAN;
BEGIN
  dir.handle := pas_sys_dir_open(BufCStr(path));
  SysDirOpen := dir.handle <> NIL;
END;

FUNCTION SysDirNext(VAR dir: SysDir; VAR name: ByteBuf;
                    VAR kind: INTEGER32): INTEGER32;
VAR
  result: CINT;
BEGIN
  BufClear(name);
  BufReserve(name, SYS_PATH_CAP);
  result := pas_sys_dir_next(dir.handle, BufPtr(name), SYS_PATH_CAP);
  IF result > 0 THEN
  BEGIN
    kind := result - 1;
    BufAppendCStr(name, BufPtr(name));
    SysDirNext := SYS_DIR_ENTRY;
  END
  ELSE
    SysDirNext := result;
END;

FUNCTION SysDirClose(VAR dir: SysDir): BOOLEAN;
VAR
  result: CINT;
BEGIN
  IF dir.handle = NIL THEN
    SysDirClose := TRUE
  ELSE
  BEGIN
    result := pas_sys_dir_close(dir.handle);
    dir.handle := NIL;
    SysDirClose := result = SYS_OK;
  END;
END;

FUNCTION SysTempDirCreate(VAR prefix: ByteBuf; VAR path: ByteBuf): BOOLEAN;
BEGIN
  BufClear(path);
  BufReserve(path, SYS_PATH_CAP);
  IF pas_sys_temp_dir(BufCStr(prefix), BufPtr(path), SYS_PATH_CAP) = SYS_OK THEN
  BEGIN
    BufAppendCStr(path, BufPtr(path));
    SysTempDirCreate := TRUE;
  END
  ELSE
    SysTempDirCreate := FALSE;
END;

FUNCTION SysRemoveTree(VAR path: ByteBuf): BOOLEAN;
BEGIN
  SysRemoveTree := pas_sys_remove_tree(BufCStr(path)) = SYS_OK;
END;

PROCEDURE SysArgsInit(VAR args: SysArgs);
BEGIN
  args.count := 0;
  BufInit(args.payload, 0);
END;

PROCEDURE SysArgsFree(VAR args: SysArgs);
BEGIN
  BufFree(args.payload);
  args.count := 0;
END;

FUNCTION SysArgsAdd(VAR args: SysArgs; VAR arg: ByteBuf): BOOLEAN;
BEGIN
  IF (args.count >= SYS_MAX_ARGS) OR
     (BufIndexOfChar(arg, CHR(0), 0) >= 0) THEN
    SysArgsAdd := FALSE
  ELSE
  BEGIN
    BufAppendBuf(args.payload, arg);
    BufAppendChar(args.payload, CHR(0));
    args.count := args.count + 1;
    SysArgsAdd := TRUE;
  END;
END;

FUNCTION SysExec(VAR executable: ByteBuf; VAR args: SysArgs;
                 timeout_ms: INTEGER32; VAR exit_code: INTEGER32;
                 VAR term_signal: INTEGER32; VAR diagnostics: ByteBuf): INTEGER32;
VAR
  diagnostic_len: INTEGER32;
  result: CINT;
BEGIN
  BufClear(diagnostics);
  BufReserve(diagnostics, SYS_DIAGNOSTIC_CAP);
  exit_code := -1;
  term_signal := 0;
  result := pas_sys_exec(BufCStr(executable), BufCStr(args.payload),
                         BufLen(args.payload), timeout_ms,
                         ADR exit_code, ADR term_signal,
                         BufPtr(diagnostics), SYS_DIAGNOSTIC_CAP,
                         ADR diagnostic_len);
  IF diagnostic_len > 0 THEN
    BufAppendCStr(diagnostics, BufPtr(diagnostics));
  SysExec := result;
END;

BEGIN
END.
