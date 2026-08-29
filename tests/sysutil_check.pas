(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'sysutil.inc'*)
PROGRAM sysutil_check(input, output);

USES bytebuf, sysutil;

FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

PROCEDURE Fail(msg: ByteStr);
BEGIN
  exit(1);
END;

PROCEDURE Check(ok: BOOLEAN; msg: ByteStr);
BEGIN
  IF NOT ok THEN Fail(msg);
END;

PROCEDURE CheckDirectory;
VAR
  path, name: ByteBuf;
  dir: SysDir;
  kind, result, count: INTEGER32;
  alpha_seen, hidden_seen, nested_seen, link_seen, child_seen: BOOLEAN;
BEGIN
  BufInit(path, 0);
  BufInit(name, 0);
  BufAppendCStr(path, pas_arg_value(1));
  Check(SysDirOpen(path, dir), 'open fixture');
  count := 0;
  alpha_seen := FALSE;
  hidden_seen := FALSE;
  nested_seen := FALSE;
  link_seen := FALSE;
  child_seen := FALSE;
  result := SysDirNext(dir, name, kind);
  WHILE result = SYS_DIR_ENTRY DO
  BEGIN
    IF BufEqualsStr(name, 'alpha') THEN
    BEGIN
      Check(kind = SYS_ENTRY_FILE, 'alpha kind');
      alpha_seen := TRUE;
    END;
    IF BufEqualsStr(name, '.hidden') THEN
    BEGIN
      Check(kind = SYS_ENTRY_FILE, 'hidden kind');
      hidden_seen := TRUE;
    END;
    IF BufEqualsStr(name, 'nested') THEN
    BEGIN
      Check(kind = SYS_ENTRY_DIR, 'nested kind');
      nested_seen := TRUE;
    END;
    IF BufEqualsStr(name, 'alpha-link') THEN
    BEGIN
      Check(kind = SYS_ENTRY_OTHER, 'symlink kind');
      link_seen := TRUE;
    END;
    IF BufEqualsStr(name, 'child') THEN child_seen := TRUE;
    count := count + 1;
    result := SysDirNext(dir, name, kind);
  END;
  Check(result = SYS_DIR_END, 'directory end');
  Check(count = 4, 'directory count');
  Check(alpha_seen AND hidden_seen AND nested_seen AND link_seen,
        'directory entries');
  Check(NOT child_seen, 'directory is shallow');
  Check(SysDirClose(dir), 'directory close');
  BufFree(name);
  BufFree(path);
END;

PROCEDURE CheckTemp;
VAR
  prefix, path, file_path, data, got: ByteBuf;
  dir: SysDir;
BEGIN
  BufInit(prefix, 0);
  BufInit(path, 0);
  BufAppendStr(prefix, 'pascal-sysutil-');
  Check(SysTempDirCreate(prefix, path), 'create temp dir');
  Check(SysDirOpen(path, dir), 'open temp dir');
  Check(SysDirClose(dir), 'close temp dir');
  BufInit(file_path, 0);
  BufInit(data, 0);
  BufInit(got, 0);
  BufAppendBuf(file_path, path);
  BufAppendStr(file_path, '/sample');
  BufAppendStr(data, 'contents');
  Check(SysWriteFile(file_path, data), 'write temp file');
  Check(SysReadFile(file_path, got), 'read temp file');
  Check(BufEqualsStr(got, 'contents'), 'read temp contents');
  Check(SysRemoveTree(path), 'remove temp dir');
  Check(NOT SysDirOpen(path, dir), 'removed temp dir');
  BufFree(got);
  BufFree(data);
  BufFree(file_path);
  BufFree(path);
  BufFree(prefix);
END;

PROCEDURE CheckExec;
VAR
  executable, argument, diagnostics: ByteBuf;
  args: SysArgs;
  exit_code, signal, result: INTEGER32;
BEGIN
  BufInit(executable, 0);
  BufInit(argument, 0);
  BufInit(diagnostics, 0);
  SysArgsInit(args);

  BufAppendStr(executable, '/bin/true');
  result := SysExec(executable, args, 1000, exit_code, signal, diagnostics);
  Check((result = SYS_OK) AND (exit_code = 0), 'true exit');

  BufClear(executable);
  BufAppendStr(executable, '/bin/false');
  result := SysExec(executable, args, 1000, exit_code, signal, diagnostics);
  Check((result = SYS_OK) AND (exit_code <> 0), 'false exit');

  BufClear(executable);
  BufAppendStr(executable, '/bin/sleep');
  BufAppendChar(argument, '2');
  Check(SysArgsAdd(args, argument), 'sleep argument');
  result := SysExec(executable, args, 20, exit_code, signal, diagnostics);
  Check(result = SYS_TIMEOUT, 'sleep timeout');

  SysArgsFree(args);
  BufFree(diagnostics);
  BufFree(argument);
  BufFree(executable);
END;

BEGIN
  CheckDirectory;
  CheckTemp;
  CheckExec;
  WRITELN('sysutil: all checks passed');
END.
