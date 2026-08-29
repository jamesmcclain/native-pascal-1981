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

FUNCTION BufSame(VAR left, right: ByteBuf): BOOLEAN;
VAR
  i: INTEGER32;
BEGIN
  BufSame := FALSE;
  IF BufLen(left) <> BufLen(right) THEN RETURN;
  i := 0;
  WHILE (i < BufLen(left)) AND (BufAt(left, i) = BufAt(right, i)) DO
    i := i + 1;
  BufSame := i = BufLen(left);
END;

FUNCTION HasExpectedSplitPoints: BOOLEAN;
VAR
  line_count, first, second: INTEGER32;
BEGIN
  { These are the generator's two 40%/75% rounded line boundaries.  The
    bounds are the contract: every cut starts after line one and leaves two
    lines of continuation. }
  HasExpectedSplitPoints := TRUE;
  FOR line_count := 6 TO 50 DO
    IF (line_count = 6) OR (line_count = 10) OR
       (line_count = 20) OR (line_count = 30) OR (line_count = 50) THEN
    BEGIN
      first := (line_count * 4 + 5) DIV 10;
      second := (line_count * 3 + 2) DIV 4;
      IF first < 1 THEN first := 1;
      IF second < 1 THEN second := 1;
      IF first > line_count - 2 THEN first := line_count - 2;
      IF second > line_count - 2 THEN second := line_count - 2;
      IF (first < 1) OR (first > line_count - 2) OR
         (second < 1) OR (second > line_count - 2) THEN
        HasExpectedSplitPoints := FALSE;
      IF (line_count = 30) AND (first = second) THEN
        HasExpectedSplitPoints := FALSE;
    END;
END;

VAR
  corpus_dir, compiler, source_root, name, path, source, original, reconstructed,
  temp_dir, candidate, prefix, diagnostics: ByteBuf;
  dir: SysDir;
  args: SysArgs;
  root, item, cursor: ADRMEM;
  kind, next, eligible, built, invalid, result, exit_code, term_signal,
  name_count, i, j: INTEGER32;
  id, swapped: ByteStr;
  names: CorpusNames;
  cleanup_ok: BOOLEAN;

BEGIN
  BufInit(corpus_dir, 0);
  BufInit(compiler, 0);
  BufInit(source_root, 0);
  BufInit(name, 0);
  BufInit(path, 0);
  BufInit(source, 0);
  BufInit(original, 0);
  BufInit(reconstructed, 0);
  BufInit(temp_dir, 0);
  BufInit(candidate, 0);
  BufInit(prefix, 0);
  BufInit(diagnostics, 0);
  BufAppendCStr(corpus_dir, pas_arg_value(1));
  BufAppendCStr(compiler, pas_arg_value(2));
  BufAppendCStr(source_root, pas_arg_value(3));
  BufAppendStr(prefix, 'pascal-corpus-');

  IF (BufLen(corpus_dir) = 0) OR (BufLen(compiler) = 0) OR
     (BufLen(source_root) = 0) THEN
  BEGIN
    WRITELN('usage: corpus_reference CORPUS_DIR COMPILER SOURCE_ROOT');
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
  IF NOT HasExpectedSplitPoints THEN
  BEGIN
    WRITELN('INVALID corpus split-point rules');
    invalid := invalid + 1;
  END;

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
  IF (name_count <= 20) OR (name_count >= 150) THEN
  BEGIN
    WRITELN('INVALID corpus file count ', name_count);
    invalid := invalid + 1;
  END;

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
          cursor := JxGet(item, 'cursor');
          IF NOT JxIsObject(item) OR NOT JxIsString(JxGet(item, 'id')) OR
             NOT JxIsString(JxGet(item, 'goal')) OR
             NOT JxIsString(JxGet(item, 'buffer')) OR
             NOT JxIsObject(cursor) OR
             NOT JxIsNumber(JxGet(cursor, 'line')) OR
             NOT JxIsNumber(JxGet(cursor, 'column')) OR
             NOT JxIsString(JxGet(item, 'reference_continuation')) OR
             NOT JxIsBool(JxGet(item, 'compiles_when_appended')) THEN
          BEGIN
            invalid := invalid + 1;
            WRITE('INVALID ');
            WriteBuf(name, 160);
            WRITELN;
          END
          ELSE
          BEGIN
            IF JxIsTrue(JxGet(item, 'generated')) AND
               JxIsString(JxGet(item, 'source_file')) THEN
            BEGIN
              BufClear(path);
              BufAppendBuf(path, source_root);
              BufAppendChar(path, '/');
              JxGetStrToBuf(item, 'source_file', path);
              IF SysReadFile(path, original) THEN
              BEGIN
                BufClear(reconstructed);
                BufClear(diagnostics);
                JxGetStrToBuf(item, 'buffer', reconstructed);
                JxGetStrToBuf(item, 'reference_continuation', diagnostics);
                BufAppendBuf(reconstructed, diagnostics);
                IF NOT BufSame(original, reconstructed) THEN
                BEGIN
                  invalid := invalid + 1;
                  WRITE('INVALID reconstruction ');
                  WriteBuf(name, 160);
                  WRITELN;
                END;
              END;
            END;
            IF JxIsTrue(JxGet(item, 'compiles_when_appended')) THEN
            BEGIN
              eligible := eligible + 1;
              BufClear(source);
              BufClear(diagnostics);
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
