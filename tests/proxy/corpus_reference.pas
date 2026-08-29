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

TYPE
  CorpusNames = ARRAY [0..127] OF ByteStr;

FUNCTION StrLess(VAR a, b: ByteStr): BOOLEAN;
VAR
  i, limit: INTEGER32;
BEGIN
  limit := ORD(a[0]);
  IF ORD(b[0]) < limit THEN limit := ORD(b[0]);
  i := 1;
  WHILE (i <= limit) AND (a[i] = b[i]) DO i := i + 1;
  IF i > limit THEN
    StrLess := ORD(a[0]) < ORD(b[0])
  ELSE
    StrLess := ORD(a[i]) < ORD(b[i]);
END;

VAR
  corpus_dir, compiler, name, path, source, temp_dir, candidate, prefix, diagnostics: ByteBuf;
  dir: SysDir;
  args: SysArgs;
  root, item: ADRMEM;
  kind, next, eligible, built, invalid, result, exit_code, term_signal,
  name_count, i, j: INTEGER32;
  id, swapped: ByteStr;
  names: CorpusNames;
  cleanup_ok: BOOLEAN;

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
  name_count := 0;

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
      IF name_count = 128 THEN
      BEGIN
        invalid := invalid + 1;
        WRITELN('INVALID too many corpus files');
      END
      ELSE
      BEGIN
        BufSliceToStr(name, 0, BufLen(name), names[name_count]);
        name_count := name_count + 1;
      END;
    END;
    next := SysDirNext(dir, name, kind);
  END;
  IF NOT SysDirClose(dir) THEN invalid := invalid + 1;

  IF name_count > 1 THEN
    FOR i := 1 TO name_count - 1 DO
    BEGIN
      j := i;
      WHILE (j > 0) AND StrLess(names[j], names[j - 1]) DO
      BEGIN
        swapped := names[j];
        names[j] := names[j - 1];
        names[j - 1] := swapped;
        j := j - 1;
      END;
    END;

  IF name_count > 0 THEN
    FOR i := 0 TO name_count - 1 DO
    BEGIN
      BufClear(name);
      BufAppendStr(name, names[i]);
      BufClear(path);
      BufAppendBuf(path, corpus_dir);
      BufAppendChar(path, '/');
      BufAppendBuf(path, name);
      IF NOT SysReadFile(path, source) THEN
      BEGIN
        invalid := invalid + 1;
        WRITE('INVALID unreadable ');
        WriteBuf(name, 160);
        WRITELN;
      END
      ELSE
      BEGIN
        root := JxParseBuf(source);
        IF root = NIL THEN
        BEGIN
          invalid := invalid + 1;
          WRITE('INVALID JSON ');
          WriteBuf(name, 160);
          WRITELN;
        END
        ELSE
        BEGIN
          item := root;
          IF NOT JxIsObject(item) OR NOT JxIsString(JxGet(item, 'id')) OR
             NOT JxIsString(JxGet(item, 'buffer')) OR
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
            IF NOT SysWriteFile(candidate, source) THEN
            BEGIN
              invalid := invalid + 1;
              WRITE('INVALID unwritable ');
              WriteBuf(name, 160);
              WRITELN;
            END
            ELSE
            BEGIN
              SysArgsInit(args);
              IF NOT SysArgsAdd(args, candidate) THEN
              BEGIN
                invalid := invalid + 1;
                WRITELN('INVALID compiler arguments');
              END
              ELSE
              BEGIN
                result := SysExec(compiler, args, 30000, exit_code, term_signal,
                                  diagnostics);
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
              SysArgsFree(args);
            END;
          END;
          JxDelete(root);
        END;
      END;
    END;

  cleanup_ok := SysRemoveTree(temp_dir);
  WRITELN(built, ' of ', eligible, ' recorded continuations compiled');
  IF (next <> SYS_DIR_END) OR (invalid <> 0) OR (built <> eligible) OR
     NOT cleanup_ok THEN exit(1);
END.
