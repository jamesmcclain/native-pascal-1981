(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'jsonx.inc'*)
(*$INCLUDE:'sysutil.inc'*)
PROGRAM corpus_reference(input, output);

USES bytebuf, jsonx, sysutil;

FUNCTION pas_arg_value(index: CINT): ADRMEM [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;

PROCEDURE WriteBuf(VAR b: ByteBuf; limit: INTEGER32);
VAR
  i, n: INTEGER32;
BEGIN
  n := BufLen(b);
  IF n > limit THEN n := limit;
  FOR i := 0 TO n - 1 DO WRITE(BufAt(b, i));
END;

FUNCTION IsJsonName(VAR name: ByteBuf): BOOLEAN;
VAR
  n: INTEGER32;
BEGIN
  n := BufLen(name);
  IsJsonName := (n >= 6) AND BufMatchesStrAt(name, n - 5, '.json');
END;

VAR
  corpus_dir, compiler, name, path, source, temp_dir, candidate, prefix, diagnostics: ByteBuf;
  dir: SysDir;
  args: SysArgs;
  root, item: ADRMEM;
  kind, next, eligible, built, invalid, result, exit_code, term_signal: INTEGER32;
  id: ByteStr;

BEGIN
  BufInit(corpus_dir, 0);
  BufInit(compiler, 0);
  BufInit(name, 0);
  BufInit(path, 0);
  BufInit(source, 0);
  BufInit(temp_dir, 0);
  BufInit(candidate, 0);
  BufInit(prefix, 0);
  BufInit(diagnostics, 0);
  BufAppendCStr(corpus_dir, pas_arg_value(1));
  BufAppendCStr(compiler, pas_arg_value(2));
  BufAppendStr(prefix, 'pascal-corpus-');

  IF (BufLen(corpus_dir) = 0) OR (BufLen(compiler) = 0) THEN
  BEGIN
    WRITELN('usage: corpus_reference CORPUS_DIR COMPILER');
    exit(2);
  END;
  IF NOT SysTempDirCreate(prefix, temp_dir) THEN
  BEGIN
    WRITELN('corpus reference: could not create temporary directory');
    exit(1);
  END;
  BufAppendBuf(candidate, temp_dir);
  BufAppendStr(candidate, '/candidate.pas');
  eligible := 0;
  built := 0;
  invalid := 0;

  IF NOT SysDirOpen(corpus_dir, dir) THEN
  BEGIN
    WRITELN('corpus reference: could not open corpus directory');
    SysRemoveTree(temp_dir);
    exit(1);
  END;
  next := SysDirNext(dir, name, kind);
  WHILE next = SYS_DIR_ENTRY DO
  BEGIN
    IF (kind = SYS_ENTRY_FILE) AND IsJsonName(name) THEN
    BEGIN
      BufClear(path);
      BufAppendBuf(path, corpus_dir);
      BufAppendChar(path, '/');
      BufAppendBuf(path, name);
      IF SysReadFile(path, source) THEN
      BEGIN
        root := JxParseBuf(source);
        IF root <> NIL THEN
        BEGIN
          item := root;
          IF NOT JxIsObject(item) OR NOT JxIsString(JxGet(item, 'buffer')) OR
             NOT JxIsString(JxGet(item, 'reference_continuation')) OR
             NOT JxIsBool(JxGet(item, 'compiles_when_appended')) THEN
          BEGIN
            invalid := invalid + 1;
            WRITE('INVALID ');
            WriteBuf(name, 160);
            WRITELN;
          END
          ELSE IF JxIsTrue(JxGet(item, 'compiles_when_appended')) THEN
          BEGIN
            eligible := eligible + 1;
            BufClear(source);
            JxGetStrToBuf(item, 'buffer', source);
            JxGetStrToBuf(item, 'reference_continuation', diagnostics);
            BufAppendBuf(source, diagnostics);
            IF SysWriteFile(candidate, source) THEN
            BEGIN
              SysArgsInit(args);
              SysArgsAdd(args, candidate);
              result := SysExec(compiler, args, 30000, exit_code, term_signal,
                                diagnostics);
              SysArgsFree(args);
              IF (result = SYS_OK) AND (exit_code = 0) THEN
                built := built + 1
              ELSE
              BEGIN
                JxGetStr(item, 'id', id);
                WRITE('FAIL ', id, ' ');
                IF result = SYS_TIMEOUT THEN
                  WRITE('compiler timed out')
                ELSE
                  WriteBuf(diagnostics, 160);
                WRITELN;
              END;
            END;
          END;
          JxDelete(root);
        END;
      END;
    END;
    next := SysDirNext(dir, name, kind);
  END;
  SysDirClose(dir);
  SysRemoveTree(temp_dir);
  WRITELN(built, ' of ', eligible, ' recorded continuations compiled');
  IF (next <> SYS_DIR_END) OR (invalid <> 0) OR (built <> eligible) THEN exit(1);
END.
