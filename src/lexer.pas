{ Pascal-1981 Native Lexer implementation in extended IBM Pascal 2.0 dialect.
  Converts Pascal source code from standard input into JSON token stream on stdout. }

(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_lex(input, output);

USES jsonutil;

{ C-FFI bindings to libcjson and stdlib }
FUNCTION cJSON_CreateArray: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateString(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNumber(num: REAL): ADRMEM [C]; EXTERN;
FUNCTION pas_int64_to_double(v: INTEGER64): REAL [C]; EXTERN;
FUNCTION cJSON_CreateBool(b: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNull: ADRMEM [C]; EXTERN;
PROCEDURE cJSON_AddItemToArray(arr: ADRMEM; item: ADRMEM) [C]; EXTERN;
PROCEDURE cJSON_AddItemToObject(obj: ADRMEM; key: ADRMEM; item: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_Print(item: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE cJSON_Delete(item: ADRMEM) [C]; EXTERN;
PROCEDURE puts(str: ADRMEM) [C]; EXTERN;
FUNCTION getchar: CINT [C]; EXTERN;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE free(ptr: ADRMEM) [C]; EXTERN;
PROCEDURE c_exit(code: CINT) [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;
FUNCTION fopen(path: ADRMEM; mode: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION fgetc(stream: ADRMEM): CINT [C]; EXTERN;
PROCEDURE fclose(stream: ADRMEM) [C]; EXTERN;

PROCEDURE TokenizeBuffer; FORWARD;

TYPE
  MetacmdFlags = RECORD
    Brave: BOOLEAN;
    Debug: BOOLEAN;
    Entry: BOOLEAN;
    GotoFlag: BOOLEAN;
    IndexCk: BOOLEAN;
    InitCk: BOOLEAN;
    LineFlag: BOOLEAN;
    List: BOOLEAN;
    MathCk: BOOLEAN;
    NilCk: BOOLEAN;
    Ocode: BOOLEAN;
    RangeCk: BOOLEAN;
    Runtime: BOOLEAN;
    StackCk: BOOLEAN;
    Symtab: BOOLEAN;
    Warn: BOOLEAN;
  END;

VAR
  root_array: ADRMEM;
  flags: MetacmdFlags;
  json_str: ADRMEM;
  
  { Source input buffer }
  src_buf: ADRMEM;
  { INTEGER32, not bare INTEGER: any source file over ~32KB (parser.pas is
    ~67KB) needs a position/length wider than a 16-bit INTEGER's ~32767
    max -- dialect gotcha #1. Every function that reads or stores a
    position derived from these (ReadBufChar's pos param, ScanIdentifier/
    ScanNumber's start_pos) must match this width or it silently truncates
    on assignment. }
  src_len, src_pos: INTEGER32;
  cur_line, cur_col: INTEGER;

  { One-shot $UNROLL(n) count, stamped onto the flags of exactly the next
    emitted token (mirrors Python Lexer._pending_unroll). }
  pending_unroll_set: BOOLEAN;
  pending_unroll_val: INTEGER;

  { $PUSH/$POP stack of ON/OFF flag snapshots. Fixed depth is fine: no
    real source nests metacommand PUSH/POP anywhere near this deep. }
  flag_stack: ARRAY [1..32] OF MetacmdFlags;
  flag_stack_top: INTEGER;

  { $INCONST-registered meta-constant names -> values (always 0 for a
    non-interactive build, matching the Python reference). }
  meta_const_names: ARRAY [1..32] OF Str255;
  meta_const_vals: ARRAY [1..32] OF INTEGER;
  meta_const_count: INTEGER;

  { A one-character LSTRING holding a close-brace character. A bare quoted
    single character lexes as a CHAR_LITERAL, not a STRING_LITERAL, so it
    cannot be passed directly where a Str255/LSTRING parameter is expected
    (only 2+ character quoted literals, like '*)', lex as strings). This is
    built once at startup and reused everywhere a one-character closer
    string is needed. }
  brace_str: Str255;

  { Trivia-attachment state for pretty81 (see docs on 'leading_comments'/
    'trailing_comment' below): ordinary comments are captured instead of
    discarded, and queued here until the next real token is emitted. A
    comment on the same source line as the token just emitted, with nothing
    already queued, attaches as that token's trailing_comment instead of
    becoming leading trivia for whatever follows. }
  pending_leading: ARRAY [1..32] OF Str255;
  pending_leading_count: INTEGER;
  last_token_line: INTEGER;
  has_last_token: BOOLEAN;

PROCEDURE InitFlags(VAR f: MetacmdFlags);
BEGIN
  f.Brave := TRUE;
  f.Debug := TRUE;
  f.Entry := FALSE;
  f.GotoFlag := FALSE;
  f.IndexCk := TRUE;
  f.InitCk := FALSE;
  f.LineFlag := FALSE;
  f.List := TRUE;
  f.MathCk := TRUE;
  f.NilCk := TRUE;
  f.Ocode := TRUE;
  f.RangeCk := TRUE;
  f.Runtime := FALSE;
  f.StackCk := TRUE;
  f.Symtab := TRUE;
  f.Warn := TRUE;
END;

PROCEDURE AddFlagToObj(obj: ADRMEM; name_str: Str255; val: BOOLEAN);
VAR
  key_ptr: ADRMEM;
BEGIN
  key_ptr := MakeCStr(name_str);
  IF val THEN
    cJSON_AddItemToObject(obj, key_ptr, cJSON_CreateBool(1))
  ELSE
    cJSON_AddItemToObject(obj, key_ptr, cJSON_CreateBool(0));
END;

FUNCTION CreateFlagsObj(VAR f: MetacmdFlags): ADRMEM;
VAR
  f_obj: ADRMEM;
  s: Str255;
BEGIN
  f_obj := cJSON_CreateObject;
  s := 'BRAVE'; AddFlagToObj(f_obj, s, f.Brave);
  s := 'DEBUG'; AddFlagToObj(f_obj, s, f.Debug);
  s := 'ENTRY'; AddFlagToObj(f_obj, s, f.Entry);
  s := 'GOTO'; AddFlagToObj(f_obj, s, f.GotoFlag);
  s := 'INDEXCK'; AddFlagToObj(f_obj, s, f.IndexCk);
  s := 'INITCK'; AddFlagToObj(f_obj, s, f.InitCk);
  s := 'LINE'; AddFlagToObj(f_obj, s, f.LineFlag);
  s := 'LIST'; AddFlagToObj(f_obj, s, f.List);
  s := 'MATHCK'; AddFlagToObj(f_obj, s, f.MathCk);
  s := 'NILCK'; AddFlagToObj(f_obj, s, f.NilCk);
  s := 'OCODE'; AddFlagToObj(f_obj, s, f.Ocode);
  s := 'RANGECK'; AddFlagToObj(f_obj, s, f.RangeCk);
  s := 'RUNTIME'; AddFlagToObj(f_obj, s, f.Runtime);
  s := 'STACKCK'; AddFlagToObj(f_obj, s, f.StackCk);
  s := 'SYMTAB'; AddFlagToObj(f_obj, s, f.Symtab);
  s := 'WARN'; AddFlagToObj(f_obj, s, f.Warn);
  CreateFlagsObj := f_obj;
END;

PROCEDURE AddToken(kind: Str255; code: INTEGER; lexeme: Str255; val_type: INTEGER; int_val: INTEGER64; real_val: REAL; str_val: Str255; line, col: INTEGER);
VAR
  tok_obj, val_item, flags_obj, comments_arr: ADRMEM;
  kind_ptr, lex_ptr, str_ptr, key_ptr: ADRMEM;
  fieldName: Str255;
  i: INTEGER;
BEGIN
  tok_obj := cJSON_CreateObject;
  
  kind_ptr := MakeCStr(kind);
  lex_ptr := MakeCStr(lexeme);

  fieldName := 'kind'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, cJSON_CreateString(kind_ptr));
  
  fieldName := 'code'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, cJSON_CreateNumber(code));

  fieldName := 'lexeme'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, cJSON_CreateString(lex_ptr));

  { Value field handling: 0=null, 1=int, 2=real, 3=str, 4=bool }
  IF val_type = 1 THEN
    val_item := cJSON_CreateNumber(pas_int64_to_double(int_val))
  ELSE IF val_type = 2 THEN
    val_item := cJSON_CreateNumber(real_val)
  ELSE IF val_type = 3 THEN
  BEGIN
    str_ptr := MakeCStr(str_val);
    val_item := cJSON_CreateString(str_ptr);
  END
  ELSE IF val_type = 4 THEN
    val_item := cJSON_CreateBool(RETYPE(CINT, int_val))
  ELSE
    val_item := cJSON_CreateNull;

  fieldName := 'value'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, val_item);

  fieldName := 'line'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, cJSON_CreateNumber(line));

  fieldName := 'column'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, cJSON_CreateNumber(col));

  flags_obj := CreateFlagsObj(flags);
  IF pending_unroll_set THEN
  BEGIN
    fieldName := 'UNROLL'; key_ptr := MakeCStr(fieldName);
    cJSON_AddItemToObject(flags_obj, key_ptr, cJSON_CreateNumber(pending_unroll_val));
    pending_unroll_set := FALSE;
  END;
  fieldName := 'flags'; key_ptr := MakeCStr(fieldName);
  cJSON_AddItemToObject(tok_obj, key_ptr, flags_obj);

  IF pending_leading_count > 0 THEN
  BEGIN
    comments_arr := cJSON_CreateArray;
    FOR i := 1 TO pending_leading_count DO
      cJSON_AddItemToArray(comments_arr, cJSON_CreateString(MakeCStr(pending_leading[i])));
    fieldName := 'leading_comments'; key_ptr := MakeCStr(fieldName);
    cJSON_AddItemToObject(tok_obj, key_ptr, comments_arr);
    pending_leading_count := 0;
  END;
  last_token_line := line;
  has_last_token := TRUE;

  cJSON_AddItemToArray(root_array, tok_obj);
END;

FUNCTION GetKeywordCode(kw: Str255): INTEGER;
BEGIN
  IF kw = 'PROGRAM' THEN GetKeywordCode := 1
  ELSE IF kw = 'MODULE' THEN GetKeywordCode := 2
  ELSE IF kw = 'INTERFACE' THEN GetKeywordCode := 3
  ELSE IF kw = 'IMPLEMENTATION' THEN GetKeywordCode := 4
  ELSE IF kw = 'USES' THEN GetKeywordCode := 5
  ELSE IF kw = 'CONST' THEN GetKeywordCode := 6
  ELSE IF kw = 'TYPE' THEN GetKeywordCode := 7
  ELSE IF kw = 'VAR' THEN GetKeywordCode := 8
  ELSE IF kw = 'VALUE' THEN GetKeywordCode := 9
  ELSE IF kw = 'LABEL' THEN GetKeywordCode := 10
  ELSE IF kw = 'PROCEDURE' THEN GetKeywordCode := 11
  ELSE IF kw = 'FUNCTION' THEN GetKeywordCode := 12
  ELSE IF kw = 'BEGIN' THEN GetKeywordCode := 13
  ELSE IF kw = 'END' THEN GetKeywordCode := 14
  ELSE IF kw = 'IF' THEN GetKeywordCode := 15
  ELSE IF kw = 'THEN' THEN GetKeywordCode := 16
  ELSE IF kw = 'ELSE' THEN GetKeywordCode := 17
  ELSE IF kw = 'FOR' THEN GetKeywordCode := 18
  ELSE IF kw = 'TO' THEN GetKeywordCode := 19
  ELSE IF kw = 'DOWNTO' THEN GetKeywordCode := 20
  ELSE IF kw = 'DO' THEN GetKeywordCode := 21
  ELSE IF kw = 'REPEAT' THEN GetKeywordCode := 22
  ELSE IF kw = 'UNTIL' THEN GetKeywordCode := 23
  ELSE IF kw = 'WHILE' THEN GetKeywordCode := 24
  ELSE IF kw = 'CASE' THEN GetKeywordCode := 25
  ELSE IF kw = 'OF' THEN GetKeywordCode := 26
  ELSE IF kw = 'OTHERWISE' THEN GetKeywordCode := 27
  ELSE IF kw = 'WITH' THEN GetKeywordCode := 28
  ELSE IF kw = 'GOTO' THEN GetKeywordCode := 29
  ELSE IF kw = 'BREAK' THEN GetKeywordCode := 30
  ELSE IF kw = 'CYCLE' THEN GetKeywordCode := 31
  ELSE IF kw = 'RETURN' THEN GetKeywordCode := 32
  ELSE IF kw = 'EXTERN' THEN GetKeywordCode := 33
  ELSE IF kw = 'EXTERNAL' THEN GetKeywordCode := 34
  ELSE IF kw = 'FORWARD' THEN GetKeywordCode := 35
  ELSE IF kw = 'PACKED' THEN GetKeywordCode := 36
  ELSE IF kw = 'SUPER' THEN GetKeywordCode := 37
  ELSE IF kw = 'ARRAY' THEN GetKeywordCode := 38
  ELSE IF kw = 'RECORD' THEN GetKeywordCode := 39
  ELSE IF kw = 'SET' THEN GetKeywordCode := 40
  ELSE IF kw = 'FILE' THEN GetKeywordCode := 41
  ELSE IF kw = 'ORIGIN' THEN GetKeywordCode := 43
  ELSE IF kw = 'READONLY' THEN GetKeywordCode := 44
  ELSE IF kw = 'PUBLIC' THEN GetKeywordCode := 45
  ELSE IF kw = 'STATIC' THEN GetKeywordCode := 46
  ELSE IF kw = 'PURE' THEN GetKeywordCode := 47
  ELSE IF kw = 'OVERLAY' THEN GetKeywordCode := 48
  ELSE IF kw = 'FORTRAN' THEN GetKeywordCode := 49
  ELSE IF kw = 'ADR' THEN GetKeywordCode := 50
  ELSE IF kw = 'SIZEOF' THEN GetKeywordCode := 51
  ELSE IF kw = 'UPPER' THEN GetKeywordCode := 52
  ELSE IF kw = 'IN' THEN GetKeywordCode := 53
  ELSE IF kw = 'DIV' THEN GetKeywordCode := 54
  ELSE IF kw = 'MOD' THEN GetKeywordCode := 55
  ELSE IF kw = 'OR' THEN GetKeywordCode := 56
  ELSE IF kw = 'XOR' THEN GetKeywordCode := 57
  ELSE IF kw = 'AND' THEN GetKeywordCode := 58
  ELSE IF kw = 'NOT' THEN GetKeywordCode := 87
  ELSE IF kw = 'UNIT' THEN GetKeywordCode := 88
  ELSE IF kw = 'VARS' THEN GetKeywordCode := 89
  ELSE IF kw = 'CONSTS' THEN GetKeywordCode := 90
  ELSE IF kw = 'NIL' THEN GetKeywordCode := 91
  ELSE IF kw = 'ADS' THEN GetKeywordCode := 92
  ELSE IF kw = 'LOWER' THEN GetKeywordCode := 93
  ELSE GetKeywordCode := 0;
END;

FUNCTION ReadBufChar(pos: INTEGER32): CHAR;
VAR
  p: ^CHAR;
BEGIN
  IF (pos >= 0) AND (pos < src_len) THEN
  BEGIN
    p := src_buf + pos;
    ReadBufChar := p^;
  END
  ELSE
    ReadBufChar := CHR(0);
END;

PROCEDURE ReadSourceInput;
VAR
  input_ch: INTEGER32;
  { INTEGER32, not bare INTEGER: cap doubles past the initial 32000-byte
    allocation for any source file over ~32KB (parser.pas is ~67KB), and a
    16-bit INTEGER silently wraps at that point (dialect gotcha #1 -- see
    ReadInputAndParseTokens in parser.pas, which already uses INTEGER32 for
    the identical growth pattern). }
  cap, i: INTEGER32;
  p, p_old, p_new: ^CHAR;
  old_buf: ADRMEM;
BEGIN
  cap := 32000;
  src_buf := malloc(cap);
  src_len := 0;
  input_ch := getchar;
  WHILE input_ch <> -1 DO
  BEGIN
    IF src_len >= cap THEN
    BEGIN
      { Reallocate buffer if full }
      old_buf := src_buf;
      cap := cap * 2;
      src_buf := malloc(cap);
      { Copy old buffer contents }
      FOR i := 0 TO src_len - 1 DO
      BEGIN
        p_old := old_buf + i;
        p_new := src_buf + i;
        p_new^ := p_old^;
      END;
      free(old_buf);
    END;
    p := src_buf + src_len;
    { getchar's CINT result is always 0..255 here (the WHILE guard above
      excludes -1), but CHR wants a plain INTEGER and the language has no
      implicit CINT/INTEGER32 -> INTEGER narrowing; RETYPE makes the
      deliberate truncation explicit. }
    p^ := CHR(RETYPE(INTEGER, input_ch));
    src_len := src_len + 1;
    input_ch := getchar;
  END;
END;

FUNCTION ReadFileToBuf(path: Str255; VAR out_buf: ADRMEM; VAR out_len: INTEGER32): BOOLEAN;
{ Reads an entire file (opened relative to the current working directory) into
  a freshly malloc'd buffer, growing it the same way ReadSourceInput grows the
  stdin buffer.  Used to splice $INCLUDE'd files' contents in as their own
  freshly-lexed token runs (see TryIncludeDirective). }
VAR
  f, path_ptr, mode_ptr: ADRMEM;
  mode_str: Str255;
  cap, i: INTEGER32;
  ch: CINT;
  p, p_old, p_new: ^CHAR;
  old_buf: ADRMEM;
BEGIN
  mode_str[0] := CHR(1);
  mode_str[1] := 'r';
  path_ptr := MakeCStr(path);
  mode_ptr := MakeCStr(mode_str);
  f := fopen(path_ptr, mode_ptr);
  IF f = NIL THEN
  BEGIN
    out_len := 0;
    ReadFileToBuf := FALSE;
  END
  ELSE
  BEGIN
    cap := 4000;
    out_buf := malloc(cap);
    out_len := 0;
    ch := fgetc(f);
    WHILE ch <> -1 DO
    BEGIN
      IF out_len >= cap THEN
      BEGIN
        old_buf := out_buf;
        cap := cap * 2;
        out_buf := malloc(cap);
        FOR i := 0 TO out_len - 1 DO
        BEGIN
          p_old := old_buf + i;
          p_new := out_buf + i;
          p_new^ := p_old^;
        END;
        free(old_buf);
      END;
      p := out_buf + out_len;
      { fgetc's CINT result is always 0..255 here (the WHILE guard above
        excludes -1), but CHR wants a plain INTEGER and the language has no
        implicit CINT/INTEGER32 -> INTEGER narrowing; RETYPE makes the
        deliberate truncation explicit. }
      p^ := CHR(RETYPE(INTEGER, ch));
      out_len := out_len + 1;
      ch := fgetc(f);
    END;
    fclose(f);
    ReadFileToBuf := TRUE;
  END;
END;

PROCEDURE AdvancePos(count: INTEGER);
VAR
  i: INTEGER;
  ch: CHAR;
BEGIN
  FOR i := 1 TO count DO
  BEGIN
    IF src_pos < src_len THEN
    BEGIN
      ch := ReadBufChar(src_pos);
      src_pos := src_pos + 1;
      IF ch = CHR(10) THEN
      BEGIN
        cur_line := cur_line + 1;
        cur_col := 1;
      END
      ELSE
        cur_col := cur_col + 1;
    END;
  END;
END;

PROCEDURE SkipWhitespace;
VAR
  ch: CHAR;
  done: BOOLEAN;
BEGIN
  done := FALSE;
  WHILE (src_pos < src_len) AND NOT done DO
  BEGIN
    ch := ReadBufChar(src_pos);
    IF (ch = ' ') OR (ch = CHR(9)) OR (ch = CHR(13)) OR (ch = CHR(10)) THEN
      AdvancePos(1)
    ELSE
      done := TRUE;
  END;
END;

FUNCTION IsAlpha(ch: CHAR): BOOLEAN;
BEGIN
  IsAlpha := ((ch >= 'a') AND (ch <= 'z')) OR ((ch >= 'A') AND (ch <= 'Z')) OR (ch = '_');
END;

FUNCTION IsDigit(ch: CHAR): BOOLEAN;
BEGIN
  IsDigit := (ch >= '0') AND (ch <= '9');
END;

FUNCTION IsAlphaOnly(ch: CHAR): BOOLEAN;
{ Like IsAlpha but without '_' -- matches Python's str.isalpha(), used only
  for the inline $THEN-lookahead scan inside a skipped $IF block. }
BEGIN
  IsAlphaOnly := ((ch >= 'a') AND (ch <= 'z')) OR ((ch >= 'A') AND (ch <= 'Z'));
END;

FUNCTION UpCaseChar(ch: CHAR): CHAR;
BEGIN
  IF (ch >= 'a') AND (ch <= 'z') THEN
    UpCaseChar := CHR(ORD(ch) - 32)
  ELSE
    UpCaseChar := ch;
END;

FUNCTION StartsWithLit(lit: Str255): BOOLEAN;
VAR
  i, n: INTEGER;
BEGIN
  n := ORD(lit[0]);
  StartsWithLit := TRUE;
  FOR i := 1 TO n DO
    IF ReadBufChar(src_pos + i - 1) <> lit[i] THEN StartsWithLit := FALSE;
END;

PROCEDURE ConsumeToLit(lit: Str255);
BEGIN
  WHILE (src_pos < src_len) AND NOT StartsWithLit(lit) DO
    AdvancePos(1);
  IF src_pos < src_len THEN AdvancePos(ORD(lit[0]));
END;

FUNCTION CaptureToLit(lit: Str255): Str255;
{ Like ConsumeToLit, but returns the text consumed (capped at 255 chars,
  the same convention ScanIdentifier uses) instead of discarding it. Used
  to capture ordinary comment bodies for pretty81's trivia-attachment. }
VAR
  start_pos: INTEGER32;
  len: INTEGER;
  text: Str255;
  i: INTEGER;
BEGIN
  start_pos := src_pos;
  len := 0;
  WHILE (src_pos < src_len) AND NOT StartsWithLit(lit) DO
  BEGIN
    IF len < 255 THEN len := len + 1;
    AdvancePos(1);
  END;
  text[0] := CHR(len);
  FOR i := 1 TO len DO
    text[i] := ReadBufChar(start_pos + i - 1);
  IF src_pos < src_len THEN AdvancePos(ORD(lit[0]));
  CaptureToLit := text;
END;

PROCEDURE RecordComment(text: Str255; start_line: INTEGER);
{ Queues a captured ordinary-comment body as trivia. A comment that starts
  on the same source line as the most recently emitted token, with nothing
  already queued as leading trivia, attaches directly to that token as its
  trailing_comment; every other comment queues as leading trivia for
  whatever real token comes next (drained in AddToken). }
VAR
  last_obj: ADRMEM;
  key_ptr, str_ptr: ADRMEM;
  fieldName: Str255;
BEGIN
  IF (pending_leading_count = 0) AND has_last_token AND (start_line = last_token_line) THEN
  BEGIN
    last_obj := cJSON_GetArrayItem(root_array, cJSON_GetArraySize(root_array) - 1);
    str_ptr := MakeCStr(text);
    fieldName := 'trailing_comment'; key_ptr := MakeCStr(fieldName);
    cJSON_AddItemToObject(last_obj, key_ptr, cJSON_CreateString(str_ptr));
  END
  ELSE IF pending_leading_count < 32 THEN
  BEGIN
    pending_leading_count := pending_leading_count + 1;
    pending_leading[pending_leading_count] := text;
  END;
END;

FUNCTION ReadMetaName: Str255;
VAR
  res: Str255;
  len: INTEGER;
BEGIN
  len := 0;
  WHILE (src_pos < src_len) AND (IsAlpha(ReadBufChar(src_pos)) OR IsDigit(ReadBufChar(src_pos))) DO
  BEGIN
    len := len + 1;
    IF len <= 255 THEN res[len] := UpCaseChar(ReadBufChar(src_pos));
    AdvancePos(1);
  END;
  res[0] := CHR(len);
  ReadMetaName := res;
END;

FUNCTION ParseSignedIntStr(s: Str255; VAR ok: BOOLEAN): INTEGER;
{ Optional leading '-' followed by 1+ digits; ok is FALSE (v=0) otherwise. }
VAR
  i, len, start, v: INTEGER;
  neg, bad: BOOLEAN;
BEGIN
  len := ORD(s[0]);
  ok := FALSE;
  v := 0;
  IF len > 0 THEN
  BEGIN
    neg := FALSE;
    start := 1;
    IF s[1] = '-' THEN
    BEGIN
      neg := TRUE;
      start := 2;
    END;
    bad := (start > len);
    FOR i := start TO len DO
      IF NOT ((s[i] >= '0') AND (s[i] <= '9')) THEN bad := TRUE;
    IF NOT bad THEN
    BEGIN
      FOR i := start TO len DO
        v := v * 10 + (ORD(s[i]) - ORD('0'));
      IF neg THEN v := -v;
      ok := TRUE;
    END;
  END;
  ParseSignedIntStr := v;
END;

FUNCTION IsFlagName(name: Str255): BOOLEAN;
BEGIN
  IsFlagName := (name = 'BRAVE') OR (name = 'DEBUG') OR (name = 'ENTRY') OR (name = 'GOTO') OR
                (name = 'INDEXCK') OR (name = 'INITCK') OR (name = 'LINE') OR (name = 'LIST') OR
                (name = 'MATHCK') OR (name = 'NILCK') OR (name = 'OCODE') OR (name = 'RANGECK') OR
                (name = 'RUNTIME') OR (name = 'STACKCK') OR (name = 'SYMTAB') OR (name = 'WARN');
END;

FUNCTION GetFlagValue(name: Str255): BOOLEAN;
BEGIN
  IF name = 'BRAVE' THEN GetFlagValue := flags.Brave
  ELSE IF name = 'DEBUG' THEN GetFlagValue := flags.Debug
  ELSE IF name = 'ENTRY' THEN GetFlagValue := flags.Entry
  ELSE IF name = 'GOTO' THEN GetFlagValue := flags.GotoFlag
  ELSE IF name = 'INDEXCK' THEN GetFlagValue := flags.IndexCk
  ELSE IF name = 'INITCK' THEN GetFlagValue := flags.InitCk
  ELSE IF name = 'LINE' THEN GetFlagValue := flags.LineFlag
  ELSE IF name = 'LIST' THEN GetFlagValue := flags.List
  ELSE IF name = 'MATHCK' THEN GetFlagValue := flags.MathCk
  ELSE IF name = 'NILCK' THEN GetFlagValue := flags.NilCk
  ELSE IF name = 'OCODE' THEN GetFlagValue := flags.Ocode
  ELSE IF name = 'RANGECK' THEN GetFlagValue := flags.RangeCk
  ELSE IF name = 'RUNTIME' THEN GetFlagValue := flags.Runtime
  ELSE IF name = 'STACKCK' THEN GetFlagValue := flags.StackCk
  ELSE IF name = 'SYMTAB' THEN GetFlagValue := flags.Symtab
  ELSE IF name = 'WARN' THEN GetFlagValue := flags.Warn
  ELSE GetFlagValue := FALSE;
END;

PROCEDURE SetFlagByName(name: Str255; val: BOOLEAN);
BEGIN
  IF name = 'BRAVE' THEN flags.Brave := val
  ELSE IF name = 'DEBUG' THEN flags.Debug := val
  ELSE IF name = 'ENTRY' THEN flags.Entry := val
  ELSE IF name = 'GOTO' THEN flags.GotoFlag := val
  ELSE IF name = 'INDEXCK' THEN flags.IndexCk := val
  ELSE IF name = 'INITCK' THEN flags.InitCk := val
  ELSE IF name = 'LINE' THEN flags.LineFlag := val
  ELSE IF name = 'LIST' THEN flags.List := val
  ELSE IF name = 'MATHCK' THEN flags.MathCk := val
  ELSE IF name = 'NILCK' THEN flags.NilCk := val
  ELSE IF name = 'OCODE' THEN flags.Ocode := val
  ELSE IF name = 'RANGECK' THEN flags.RangeCk := val
  ELSE IF name = 'RUNTIME' THEN flags.Runtime := val
  ELSE IF name = 'STACKCK' THEN flags.StackCk := val
  ELSE IF name = 'SYMTAB' THEN flags.Symtab := val
  ELSE IF name = 'WARN' THEN flags.Warn := val;
END;

PROCEDURE ApplyDebugCoupling(val: BOOLEAN);
{ $DEBUG master switch controls these sub-flags (manual Sec.4-11). }
BEGIN
  flags.Entry := val;
  flags.IndexCk := val;
  flags.InitCk := val;
  flags.MathCk := val;
  flags.NilCk := val;
  flags.RangeCk := val;
  flags.StackCk := val;
END;

FUNCTION IsIntMetaName(name: Str255): BOOLEAN;
BEGIN
  IsIntMetaName := (name = 'ERRORS') OR (name = 'LINESIZE') OR (name = 'PAGE') OR
                   (name = 'PAGEIF') OR (name = 'PAGESIZE') OR (name = 'SKIP');
END;

FUNCTION IsStrMetaName(name: Str255): BOOLEAN;
BEGIN
  IsStrMetaName := (name = 'SUBTITLE') OR (name = 'TITLE');
END;

PROCEDURE AddMetaConst(name: Str255; val: INTEGER);
VAR
  i: INTEGER;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  FOR i := 1 TO meta_const_count DO
    IF meta_const_names[i] = name THEN
    BEGIN
      meta_const_vals[i] := val;
      found := TRUE;
    END;
  IF NOT found THEN
    IF meta_const_count < 32 THEN
    BEGIN
      meta_const_count := meta_const_count + 1;
      meta_const_names[meta_const_count] := name;
      meta_const_vals[meta_const_count] := val;
    END;
END;

FUNCTION LookupMetaConst(name: Str255; VAR found: BOOLEAN): INTEGER;
VAR
  i: INTEGER;
BEGIN
  found := FALSE;
  LookupMetaConst := 0;
  FOR i := 1 TO meta_const_count DO
    IF meta_const_names[i] = name THEN
    BEGIN
      found := TRUE;
      LookupMetaConst := meta_const_vals[i];
    END;
END;

FUNCTION EvalMetaConst(token: Str255): INTEGER;
VAR
  v: INTEGER;
  ok, found: BOOLEAN;
BEGIN
  v := ParseSignedIntStr(token, ok);
  IF ok THEN
    EvalMetaConst := v
  ELSE
  BEGIN
    v := LookupMetaConst(token, found);
    IF found THEN
      EvalMetaConst := v
    ELSE IF IsFlagName(token) THEN
    BEGIN
      IF GetFlagValue(token) THEN EvalMetaConst := 1 ELSE EvalMetaConst := 0;
    END
    ELSE
      EvalMetaConst := 0;
  END;
END;

PROCEDURE PushFlags;
BEGIN
  IF flag_stack_top < 32 THEN
  BEGIN
    flag_stack_top := flag_stack_top + 1;
    flag_stack[flag_stack_top] := flags;
  END;
END;

PROCEDURE PopFlags;
BEGIN
  IF flag_stack_top > 0 THEN
  BEGIN
    flags := flag_stack[flag_stack_top];
    flag_stack_top := flag_stack_top - 1;
  END;
END;

FUNCTION ReadQuotedFilename: Str255;
VAR
  res: Str255;
  len: INTEGER;
BEGIN
  AdvancePos(1); { opening quote }
  len := 0;
  WHILE (src_pos < src_len) AND (ReadBufChar(src_pos) <> '''') DO
  BEGIN
    len := len + 1;
    IF len <= 255 THEN res[len] := ReadBufChar(src_pos);
    AdvancePos(1);
  END;
  IF src_pos < src_len THEN AdvancePos(1); { closing quote }
  res[0] := CHR(len);
  ReadQuotedFilename := res;
END;

PROCEDURE SpliceIncludedFile(fname: Str255);
{ Reads fname (relative to the current working directory -- the native
  pipeline's caller is expected to run from the including file's directory,
  same as this repository's own build/test invocations) and lexes its
  contents in place as their own fresh token run, starting at line 1 column
  1 (matching Python's lex_file, which recursively re-lexes the included
  file from scratch rather than splicing raw characters into the host
  buffer's position stream). No token is emitted for the directive itself. }
VAR
  save_buf: ADRMEM;
  save_len, save_pos: INTEGER32;
  save_line, save_col: INTEGER;
  new_buf: ADRMEM;
  new_len: INTEGER32;
  ok: BOOLEAN;
BEGIN
  save_buf := src_buf;
  save_len := src_len;
  save_pos := src_pos;
  save_line := cur_line;
  save_col := cur_col;

  ok := ReadFileToBuf(fname, new_buf, new_len);
  IF NOT ok THEN
  BEGIN
    EPrint('Lexer Error: unable to read included file');
    exit(1);
  END;

  src_buf := new_buf;
  src_len := new_len;
  src_pos := 0;
  cur_line := 1;
  cur_col := 1;

  TokenizeBuffer;

  free(new_buf);
  src_buf := save_buf;
  src_len := save_len;
  src_pos := save_pos;
  cur_line := save_line;
  cur_col := save_col;
END;

FUNCTION TryIncludeDirective: BOOLEAN;
{ Recognizes a paren-comment or brace-comment $INCLUDE directive giving a
  filename, and splices the named file's contents in via
  SpliceIncludedFile. }
VAR
  fname: Str255;
BEGIN
  TryIncludeDirective := FALSE;
  IF StartsWithLit('(*$INCLUDE:') THEN
  BEGIN
    AdvancePos(11);
    SkipWhitespace;
    IF ReadBufChar(src_pos) = '''' THEN
    BEGIN
      fname := ReadQuotedFilename;
      SkipWhitespace;
      IF StartsWithLit('*)') THEN
      BEGIN
        AdvancePos(2);
        SpliceIncludedFile(fname);
        TryIncludeDirective := TRUE;
      END;
    END;
  END
  ELSE IF StartsWithLit('{$INCLUDE:') THEN
  BEGIN
    AdvancePos(10);
    SkipWhitespace;
    IF ReadBufChar(src_pos) = '''' THEN
    BEGIN
      fname := ReadQuotedFilename;
      SkipWhitespace;
      IF StartsWithLit(brace_str) THEN
      BEGIN
        AdvancePos(1);
        SpliceIncludedFile(fname);
        TryIncludeDirective := TRUE;
      END;
    END;
  END;
END;

FUNCTION SkipSourceBlock(closer: Str255): Str255;
{ Skips a conditional-compilation source block, tracking $IF nesting, per
  Python's _skip_source_block. Assumes the current metacommand comment is
  still open; closes it (via `closer`) before scanning forward. String
  literals in the skipped text are honored so an embedded brace or paren
  comment opener cannot derail $IF/$END tracking. Returns 'ELSE' or 'END'. }
VAR
  depth, wlen: INTEGER;
  ch: CHAR;
  is_paren: BOOLEAN;
  inner_closer, tag, word: Str255;
BEGIN
  ConsumeToLit(closer);
  depth := 1;
  WHILE src_pos < src_len DO
  BEGIN
    ch := ReadBufChar(src_pos);
    IF ch = '''' THEN
    BEGIN
      AdvancePos(1);
      WHILE (src_pos < src_len) AND (ReadBufChar(src_pos) <> '''') DO
        AdvancePos(1);
      IF src_pos < src_len THEN AdvancePos(1);
    END
    ELSE IF ((ch = '(') AND (ReadBufChar(src_pos + 1) = '*')) OR (ch = '{') THEN
    BEGIN
      is_paren := (ch = '(');
      IF is_paren THEN
      BEGIN
        AdvancePos(2);
        inner_closer := '*)';
      END
      ELSE
      BEGIN
        AdvancePos(1);
        inner_closer := brace_str;
      END;
      IF ReadBufChar(src_pos) = '$' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
        tag := ReadMetaName;
        IF tag = 'IF' THEN
        BEGIN
          WHILE (src_pos < src_len) AND NOT StartsWithLit(inner_closer) DO
          BEGIN
            IF IsAlphaOnly(ReadBufChar(src_pos)) THEN
            BEGIN
              wlen := 0;
              WHILE IsAlphaOnly(ReadBufChar(src_pos)) DO
              BEGIN
                wlen := wlen + 1;
                IF wlen <= 255 THEN word[wlen] := UpCaseChar(ReadBufChar(src_pos));
                AdvancePos(1);
              END;
              word[0] := CHR(wlen);
              IF word = 'THEN' THEN BREAK;
            END
            ELSE
              AdvancePos(1);
          END;
          depth := depth + 1;
          ConsumeToLit(inner_closer);
        END
        ELSE IF (tag = 'END') AND (depth = 1) THEN
        BEGIN
          ConsumeToLit(inner_closer);
          SkipSourceBlock := 'END';
          RETURN;
        END
        ELSE IF (tag = 'ELSE') AND (depth = 1) THEN
        BEGIN
          ConsumeToLit(inner_closer);
          SkipSourceBlock := 'ELSE';
          RETURN;
        END
        ELSE IF tag = 'END' THEN
        BEGIN
          depth := depth - 1;
          ConsumeToLit(inner_closer);
        END
        ELSE
          ConsumeToLit(inner_closer);
      END
      ELSE
        ConsumeToLit(inner_closer);
    END
    ELSE
      AdvancePos(1);
  END;
  SkipSourceBlock := 'END';
END;

PROCEDURE ParseMetacommandComment(closer: Str255);
{ Parses and acts on one or more comma-separated metacommands, per Python's
  parse_metacommand_comment. Called with '$' as the current character;
  advances past `closer` before returning. }
VAR
  name, const_token, kw, ident, count_token, numstr, result_str: Str255;
  cond, nlen: INTEGER;
  ok, val: BOOLEAN;
  ch: CHAR;
BEGIN
  AdvancePos(1); { consume '$' }
  WHILE TRUE DO
  BEGIN
    SkipWhitespace;
    IF (src_pos >= src_len) OR StartsWithLit(closer) THEN BREAK;
    IF NOT IsAlpha(ReadBufChar(src_pos)) THEN BREAK;

    name := ReadMetaName;
    SkipWhitespace;

    IF name = 'IF' THEN
    BEGIN
      const_token[0] := CHR(0);
      IF IsDigit(ReadBufChar(src_pos)) THEN
      BEGIN
        nlen := 0;
        WHILE IsDigit(ReadBufChar(src_pos)) DO
        BEGIN
          nlen := nlen + 1;
          IF nlen <= 255 THEN const_token[nlen] := ReadBufChar(src_pos);
          AdvancePos(1);
        END;
        const_token[0] := CHR(nlen);
      END
      ELSE IF (ReadBufChar(src_pos) = '-') AND IsDigit(ReadBufChar(src_pos + 1)) THEN
      BEGIN
        const_token[1] := '-';
        nlen := 1;
        AdvancePos(1);
        WHILE IsDigit(ReadBufChar(src_pos)) DO
        BEGIN
          nlen := nlen + 1;
          IF nlen <= 255 THEN const_token[nlen] := ReadBufChar(src_pos);
          AdvancePos(1);
        END;
        const_token[0] := CHR(nlen);
      END
      ELSE IF IsAlpha(ReadBufChar(src_pos)) THEN
        const_token := ReadMetaName;

      SkipWhitespace;
      IF ReadBufChar(src_pos) = '$' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
        kw := ReadMetaName;
        IF kw <> 'THEN' THEN
        BEGIN
          ConsumeToLit(closer);
          RETURN;
        END;
      END;

      cond := EvalMetaConst(const_token);
      IF cond <= 0 THEN
      BEGIN
        result_str := SkipSourceBlock(closer);
        IF result_str = 'END' THEN RETURN;
        { result_str = 'ELSE': fall through, resume normal tokenizing into
          the else-branch; the eventual $END marker will be a no-op. }
      END
      ELSE
        ConsumeToLit(closer);
      RETURN;
    END

    ELSE IF name = 'ELSE' THEN
    BEGIN
      result_str := SkipSourceBlock(closer);
      RETURN;
    END

    ELSE IF name = 'END' THEN
    BEGIN
      ConsumeToLit(closer);
      RETURN;
    END

    ELSE IF name = 'PUSH' THEN
      PushFlags

    ELSE IF name = 'POP' THEN
      PopFlags

    ELSE IF name = 'MESSAGE' THEN
    BEGIN
      IF ReadBufChar(src_pos) = ':' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
      END;
      IF ReadBufChar(src_pos) = '''' THEN
      BEGIN
        AdvancePos(1);
        WHILE (src_pos < src_len) AND (ReadBufChar(src_pos) <> '''') DO
          AdvancePos(1);
        IF src_pos < src_len THEN AdvancePos(1);
      END;
    END

    ELSE IF name = 'INCONST' THEN
    BEGIN
      IF ReadBufChar(src_pos) = ':' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
      END;
      ident[0] := CHR(0);
      IF IsAlpha(ReadBufChar(src_pos)) THEN
        ident := ReadMetaName;
      IF ORD(ident[0]) > 0 THEN
        AddMetaConst(ident, 0);
    END

    ELSE IF name = 'UNROLL' THEN
    BEGIN
      IF ReadBufChar(src_pos) = ':' THEN AdvancePos(1);
      SkipWhitespace;
      count_token[0] := CHR(0);
      IF IsDigit(ReadBufChar(src_pos)) THEN
      BEGIN
        nlen := 0;
        WHILE IsDigit(ReadBufChar(src_pos)) DO
        BEGIN
          nlen := nlen + 1;
          IF nlen <= 255 THEN count_token[nlen] := ReadBufChar(src_pos);
          AdvancePos(1);
        END;
        count_token[0] := CHR(nlen);
      END
      ELSE IF IsAlpha(ReadBufChar(src_pos)) THEN
        count_token := ReadMetaName;
      IF ORD(count_token[0]) > 0 THEN
      BEGIN
        pending_unroll_set := TRUE;
        pending_unroll_val := EvalMetaConst(count_token);
      END;
    END

    ELSE IF IsFlagName(name) THEN
    BEGIN
      IF ReadBufChar(src_pos) = '+' THEN
      BEGIN
        AdvancePos(1);
        val := TRUE;
      END
      ELSE IF ReadBufChar(src_pos) = '-' THEN
      BEGIN
        AdvancePos(1);
        val := FALSE;
      END
      ELSE IF ReadBufChar(src_pos) = ':' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
        nlen := 0;
        IF (ReadBufChar(src_pos) = '+') OR (ReadBufChar(src_pos) = '-') THEN
        BEGIN
          nlen := 1;
          numstr[1] := ReadBufChar(src_pos);
          AdvancePos(1);
        END;
        WHILE IsDigit(ReadBufChar(src_pos)) DO
        BEGIN
          nlen := nlen + 1;
          IF nlen <= 255 THEN numstr[nlen] := ReadBufChar(src_pos);
          AdvancePos(1);
        END;
        numstr[0] := CHR(nlen);
        val := ParseSignedIntStr(numstr, ok) > 0;
        IF NOT ok THEN val := TRUE;
      END
      ELSE
        val := TRUE;

      SetFlagByName(name, val);
      IF name = 'DEBUG' THEN ApplyDebugCoupling(val);
      IF (name = 'LINE') AND val THEN flags.Entry := TRUE;
    END

    ELSE IF IsIntMetaName(name) THEN
    BEGIN
      IF ReadBufChar(src_pos) = ':' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
        IF (ReadBufChar(src_pos) = '+') OR (ReadBufChar(src_pos) = '-') THEN AdvancePos(1);
        WHILE IsDigit(ReadBufChar(src_pos)) DO AdvancePos(1);
      END;
    END

    ELSE IF IsStrMetaName(name) THEN
    BEGIN
      IF ReadBufChar(src_pos) = ':' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
        IF ReadBufChar(src_pos) = '''' THEN
        BEGIN
          AdvancePos(1);
          WHILE (src_pos < src_len) AND (ReadBufChar(src_pos) <> '''') DO
            AdvancePos(1);
          IF src_pos < src_len THEN AdvancePos(1);
        END
        ELSE IF IsAlpha(ReadBufChar(src_pos)) THEN
          ident := ReadMetaName; { discard }
      END;
    END

    ELSE
    BEGIN
      IF (ReadBufChar(src_pos) = '+') OR (ReadBufChar(src_pos) = '-') THEN
        AdvancePos(1)
      ELSE IF ReadBufChar(src_pos) = ':' THEN
      BEGIN
        AdvancePos(1);
        SkipWhitespace;
        IF ReadBufChar(src_pos) = '''' THEN
        BEGIN
          AdvancePos(1);
          WHILE (src_pos < src_len) AND (ReadBufChar(src_pos) <> '''') DO
            AdvancePos(1);
          IF src_pos < src_len THEN AdvancePos(1);
        END
        ELSE
        BEGIN
          ch := ReadBufChar(src_pos);
          WHILE (src_pos < src_len) AND (ch <> ' ') AND (ch <> CHR(9)) AND
                (ch <> ',') AND (ch <> '}') AND NOT StartsWithLit('*)') DO
          BEGIN
            AdvancePos(1);
            ch := ReadBufChar(src_pos);
          END;
        END;
      END;
    END;

    SkipWhitespace;
    IF ReadBufChar(src_pos) = ',' THEN
    BEGIN
      AdvancePos(1);
      SkipWhitespace;
      IF ReadBufChar(src_pos) = '$' THEN AdvancePos(1);
    END
    ELSE
      BREAK;
  END;
  ConsumeToLit(closer);
END;

PROCEDURE SkipComments;
{ Skips whitespace, $INCLUDE directives (emitting a token for each),
  and comments/metacommands, repeatedly, until a real token start or EOF
  is reached. Mirrors the effect of Python tokenize()'s per-iteration
  try_include_directive()/skip_comment() calls. }
VAR
  keep_going: BOOLEAN;
  comment_line: INTEGER;
BEGIN
  keep_going := TRUE;
  WHILE keep_going DO
  BEGIN
    SkipWhitespace;
    keep_going := FALSE;
    IF src_pos < src_len THEN
    BEGIN
      IF TryIncludeDirective THEN
        keep_going := TRUE
      ELSE IF (ReadBufChar(src_pos) = '(') AND (ReadBufChar(src_pos + 1) = '*') THEN
      BEGIN
        comment_line := cur_line;
        AdvancePos(2);
        IF ReadBufChar(src_pos) = '$' THEN
          ParseMetacommandComment('*)')
        ELSE
          RecordComment(CaptureToLit('*)'), comment_line);
        keep_going := TRUE;
      END
      ELSE IF ReadBufChar(src_pos) = '{' THEN
      BEGIN
        comment_line := cur_line;
        AdvancePos(1);
        IF ReadBufChar(src_pos) = '$' THEN
          ParseMetacommandComment(brace_str)
        ELSE
          RecordComment(CaptureToLit(brace_str), comment_line);
        keep_going := TRUE;
      END;
    END;
  END;
END;

PROCEDURE ScanIdentifier;
VAR
  start_pos: INTEGER32;
  start_line, start_col, len: INTEGER;
  lexeme, upper_str: Str255;
  i, code: INTEGER;
  ch: CHAR;
  kind_str: Str255;
BEGIN
  start_pos := src_pos;
  start_line := cur_line;
  start_col := cur_col;

  { len is a plain INTEGER (never assigned from a wide src_pos-start_pos
    subtraction, which the type checker rightly refuses to narrow
    implicitly): count characters as they're consumed instead, capping at
    255 the same way the old "len := src_pos - start_pos; IF len > 255..."
    did, but without ever holding an INTEGER32 value in an INTEGER var. }
  len := 0;
  WHILE (src_pos < src_len) AND (IsAlpha(ReadBufChar(src_pos)) OR IsDigit(ReadBufChar(src_pos))) DO
  BEGIN
    IF len < 255 THEN len := len + 1;
    AdvancePos(1);
  END;

  lexeme[0] := CHR(len);
  upper_str[0] := CHR(len);
  FOR i := 1 TO len DO
  BEGIN
    ch := ReadBufChar(start_pos + i - 1);
    lexeme[i] := ch;
    upper_str[i] := UpCaseChar(ch);
  END;
  
  IF upper_str = 'TRUE' THEN
  BEGIN
    kind_str := 'BOOLEAN_LITERAL';
    AddToken(kind_str, 85, lexeme, 4, 1, 0.0, lexeme, start_line, start_col);
  END
  ELSE IF upper_str = 'FALSE' THEN
  BEGIN
    kind_str := 'BOOLEAN_LITERAL';
    AddToken(kind_str, 85, lexeme, 4, 0, 0.0, lexeme, start_line, start_col);
  END
  ELSE
  BEGIN
    code := GetKeywordCode(upper_str);
    IF code > 0 THEN
      AddToken(upper_str, code, lexeme, 3, 0, 0.0, upper_str, start_line, start_col)
    ELSE
    BEGIN
      kind_str := 'IDENTIFIER';
      AddToken(kind_str, 80, lexeme, 3, 0, 0.0, lexeme, start_line, start_col);
    END;
  END;
END;

FUNCTION RadixDigitValue(ch: CHAR; radix: INTEGER): INTEGER;
VAR
  uch: CHAR;
  v: INTEGER;
BEGIN
  uch := UpCaseChar(ch);
  IF (uch >= '0') AND (uch <= '9') THEN
    v := ORD(uch) - ORD('0')
  ELSE IF (uch >= 'A') AND (uch <= 'F') THEN
    v := ORD(uch) - ORD('A') + 10
  ELSE
    v := -1;
  IF (v >= 0) AND (v < radix) THEN
    RadixDigitValue := v
  ELSE
    RadixDigitValue := -1;
END;

FUNCTION ClampedSpanLen(start_p, end_p: INTEGER32): INTEGER;
{ end_p - start_p, capped at 255 -- for Str255 lexeme lengths.  Computed by
  bounded counting rather than the wide subtraction "len := end_p - start_p;
  IF len > 255 THEN len := 255", which cannot assign its INTEGER32 result
  into a plain INTEGER len (the type checker refuses that narrowing, even
  though the capped value is always small in practice). }
VAR
  n: INTEGER;
  p: INTEGER32;
BEGIN
  n := 0;
  p := start_p;
  WHILE (p < end_p) AND (n < 255) DO
  BEGIN
    n := n + 1;
    p := p + 1;
  END;
  ClampedSpanLen := n;
END;

PROCEDURE ScanNumber;
VAR
  start_pos: INTEGER32;
  start_line, start_col, len, exp_val, i: INTEGER;
  int_val: INTEGER64; { the accumulated literal value can exceed 16-bit
    INTEGER's range (any decimal literal above 32767, or a radix literal
    like 16#FFFF) and can exceed 32 bits too, since INTEGER64 is a type a
    program may write a literal for -- this is purely the lexer's own scan
    accumulator, so it needs the widest host-side width regardless of the
    dialect's own native INTEGER width. It was INTEGER32, which silently
    wrapped a literal like 5000000000 to 705032704. exp_val stays plain
    INTEGER: it only ever counts a REAL literal's decimal exponent digits
    (used as a FOR loop bound below, which must match i's own INTEGER
    type), never the literal's own value. }
  radix, digit_val, look: INTEGER;
  real_val, frac_part, frac_scale: REAL;
  exp_neg: BOOLEAN;
  lexeme: Str255;
  ch: CHAR;
  kind_str: Str255;
BEGIN
  start_pos := src_pos;
  start_line := cur_line;
  start_col := cur_col;
  int_val := 0;

  WHILE (src_pos < src_len) AND IsDigit(ReadBufChar(src_pos)) DO
  BEGIN
    ch := ReadBufChar(src_pos);
    int_val := int_val * 10 + (ORD(ch) - ORD('0'));
    AdvancePos(1);
  END;

  IF (src_pos < src_len) AND (ReadBufChar(src_pos) = '#') THEN
  BEGIN
    { Radix literal, e.g. 16#FF -- the digit run just scanned is the base.
      int_val is INTEGER64 (it accumulates any digit run's full value), but a
      radix base is always small and the language has no implicit narrowing;
      RETYPE makes the deliberate truncation explicit. }
    radix := RETYPE(INTEGER, int_val);   { a base is always small }
    AdvancePos(1); { consume '#' }
    int_val := 0;
    WHILE (src_pos < src_len) AND (RadixDigitValue(ReadBufChar(src_pos), radix) >= 0) DO
    BEGIN
      digit_val := RadixDigitValue(ReadBufChar(src_pos), radix);
      int_val := int_val * radix + digit_val;
      AdvancePos(1);
    END;

    len := ClampedSpanLen(start_pos, src_pos);
    lexeme[0] := CHR(len);
    FOR i := 1 TO len DO
      lexeme[i] := ReadBufChar(start_pos + i - 1);

    kind_str := 'INTEGER_LITERAL';
    AddToken(kind_str, 81, lexeme, 1, int_val, 0.0, lexeme, start_line, start_col);
  END
  ELSE IF (src_pos < src_len) AND (ReadBufChar(src_pos) = '.') AND
          (src_pos + 1 < src_len) AND IsDigit(ReadBufChar(src_pos + 1)) THEN
  BEGIN
    { Real literal: digit+ '.' digit+ [ ('E'|'e') ['+'|'-'] digit+ ].
      The leading '..' range operator is excluded above by requiring a
      digit right after the dot. }
    AdvancePos(1); { consume '.' }
    real_val := pas_int64_to_double(int_val);
    frac_part := 0.0;
    frac_scale := 1.0;
    WHILE (src_pos < src_len) AND IsDigit(ReadBufChar(src_pos)) DO
    BEGIN
      ch := ReadBufChar(src_pos);
      frac_scale := frac_scale / 10.0;
      frac_part := frac_part + (ORD(ch) - ORD('0')) * frac_scale;
      AdvancePos(1);
    END;
    real_val := real_val + frac_part;

    { Only consume 'E'/'e' as an exponent marker if it is followed by an
      optional sign and then at least one digit -- otherwise leave it for
      the next token (matches the Python lexer's _read_exponent lookahead;
      e.g. an identifier immediately after a real literal must not be
      swallowed). }
    IF (src_pos < src_len) AND
       ((ReadBufChar(src_pos) = 'E') OR (ReadBufChar(src_pos) = 'e')) THEN
    BEGIN
      look := 1;
      IF (src_pos + look < src_len) AND
         ((ReadBufChar(src_pos + look) = '+') OR (ReadBufChar(src_pos + look) = '-')) THEN
        look := look + 1;
      IF (src_pos + look < src_len) AND IsDigit(ReadBufChar(src_pos + look)) THEN
      BEGIN
        AdvancePos(1); { consume 'E'/'e' }
        exp_neg := FALSE;
        IF (src_pos < src_len) AND (ReadBufChar(src_pos) = '+') THEN
          AdvancePos(1)
        ELSE IF (src_pos < src_len) AND (ReadBufChar(src_pos) = '-') THEN
        BEGIN
          exp_neg := TRUE;
          AdvancePos(1);
        END;
        exp_val := 0;
        WHILE (src_pos < src_len) AND IsDigit(ReadBufChar(src_pos)) DO
        BEGIN
          exp_val := exp_val * 10 + (ORD(ReadBufChar(src_pos)) - ORD('0'));
          AdvancePos(1);
        END;
        FOR i := 1 TO exp_val DO
          IF exp_neg THEN
            real_val := real_val / 10.0
          ELSE
            real_val := real_val * 10.0;
      END;
    END;

    len := ClampedSpanLen(start_pos, src_pos);
    lexeme[0] := CHR(len);
    FOR i := 1 TO len DO
      lexeme[i] := ReadBufChar(start_pos + i - 1);

    kind_str := 'REAL_LITERAL';
    AddToken(kind_str, 82, lexeme, 2, 0, real_val, lexeme, start_line, start_col);
  END
  ELSE
  BEGIN
    len := ClampedSpanLen(start_pos, src_pos);
    lexeme[0] := CHR(len);
    FOR i := 1 TO len DO
      lexeme[i] := ReadBufChar(start_pos + i - 1);

    kind_str := 'INTEGER_LITERAL';
    AddToken(kind_str, 81, lexeme, 1, int_val, 0.0, lexeme, start_line, start_col);
  END;
END;

PROCEDURE ScanString;
VAR
  start_line, start_col, str_len, lex_len, i: INTEGER;
  ch: CHAR;
  str_val, lexeme: Str255;
  kind_str: Str255;
BEGIN
  start_line := cur_line;
  start_col := cur_col;
  AdvancePos(1); { Skip opening quote }
  str_len := 0;

  WHILE src_pos < src_len DO
  BEGIN
    ch := ReadBufChar(src_pos);
    IF ch = '''' THEN
    BEGIN
      IF (src_pos + 1 < src_len) AND (ReadBufChar(src_pos + 1) = '''') THEN
      BEGIN
        str_len := str_len + 1;
        IF str_len <= 255 THEN str_val[str_len] := '''';
        AdvancePos(2);
      END
      ELSE
      BEGIN
        AdvancePos(1);
        BREAK;
      END;
    END
    ELSE
    BEGIN
      str_len := str_len + 1;
      IF str_len <= 255 THEN str_val[str_len] := ch;
      AdvancePos(1);
    END;
  END;

  str_val[0] := CHR(str_len);

  { lexeme must be the raw source text (opening quote, each embedded quote
    doubled, closing quote) -- parser.pas's ParseConstant/ParseFactor read
    this *lexeme*, not str_val, for StringLiteral/CharLiteral AST nodes,
    and then decode it themselves the same way the Python lexer's own
    "'" + value.replace("'", "''") + "'" round-trips. str_val (the
    already-decoded value, unquoted, embedded '' collapsed to ') is a
    separate field. }
  lex_len := 1;
  lexeme[1] := '''';
  FOR i := 1 TO str_len DO
  BEGIN
    IF str_val[i] = '''' THEN
    BEGIN
      lex_len := lex_len + 1;
      IF lex_len <= 255 THEN lexeme[lex_len] := '''';
    END;
    lex_len := lex_len + 1;
    IF lex_len <= 255 THEN lexeme[lex_len] := str_val[i];
  END;
  lex_len := lex_len + 1;
  IF lex_len <= 255 THEN lexeme[lex_len] := '''';
  IF lex_len > 255 THEN lex_len := 255;
  lexeme[0] := CHR(lex_len);

  IF str_len = 1 THEN
  BEGIN
    kind_str := 'CHAR_LITERAL';
    AddToken(kind_str, 83, lexeme, 3, 0, 0.0, str_val, start_line, start_col);
  END
  ELSE
  BEGIN
    kind_str := 'STRING_LITERAL';
    AddToken(kind_str, 84, lexeme, 3, 0, 0.0, str_val, start_line, start_col);
  END;
END;

PROCEDURE ScanSymbol;
VAR
  start_line, start_col: INTEGER;
  ch, c2: CHAR;
  kind_str, lex_str: Str255;
BEGIN
  start_line := cur_line;
  start_col := cur_col;
  ch := ReadBufChar(src_pos);
  c2 := ReadBufChar(src_pos + 1);

  IF (ch = ':') AND (c2 = '=') THEN
  BEGIN
    AdvancePos(2);
    kind_str := 'ASSIGN'; lex_str := ':=';
    AddToken(kind_str, 59, lex_str, 3, 0, 0.0, lex_str, start_line, start_col);
  END
  ELSE IF (ch = '<') AND (c2 = '>') THEN
  BEGIN
    AdvancePos(2);
    kind_str := 'NEQ'; lex_str := '<>';
    AddToken(kind_str, 61, lex_str, 3, 0, 0.0, lex_str, start_line, start_col);
  END
  ELSE IF (ch = '<') AND (c2 = '=') THEN
  BEGIN
    AdvancePos(2);
    kind_str := 'LE'; lex_str := '<=';
    AddToken(kind_str, 63, lex_str, 3, 0, 0.0, lex_str, start_line, start_col);
  END
  ELSE IF (ch = '>') AND (c2 = '=') THEN
  BEGIN
    AdvancePos(2);
    kind_str := 'GE'; lex_str := '>=';
    AddToken(kind_str, 65, lex_str, 3, 0, 0.0, lex_str, start_line, start_col);
  END
  ELSE IF (ch = '.') AND (c2 = '.') THEN
  BEGIN
    AdvancePos(2);
    kind_str := 'RANGE'; lex_str := '..';
    AddToken(kind_str, 70, lex_str, 3, 0, 0.0, lex_str, start_line, start_col);
  END
  ELSE
  BEGIN
    AdvancePos(1);
    lex_str[0] := CHR(1); lex_str[1] := ch;
    IF ch = '=' THEN BEGIN kind_str := 'EQ'; AddToken(kind_str, 60, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '<' THEN BEGIN kind_str := 'LT'; AddToken(kind_str, 62, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '>' THEN BEGIN kind_str := 'GT'; AddToken(kind_str, 64, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '+' THEN BEGIN kind_str := 'PLUS'; AddToken(kind_str, 66, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '-' THEN BEGIN kind_str := 'MINUS'; AddToken(kind_str, 67, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '*' THEN BEGIN kind_str := 'MUL'; AddToken(kind_str, 68, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '/' THEN BEGIN kind_str := 'SLASH'; AddToken(kind_str, 69, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '^' THEN BEGIN kind_str := 'POINTER'; AddToken(kind_str, 71, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '[' THEN BEGIN kind_str := 'LBRACKET'; AddToken(kind_str, 72, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = ']' THEN BEGIN kind_str := 'RBRACKET'; AddToken(kind_str, 73, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '(' THEN BEGIN kind_str := 'LPAREN'; AddToken(kind_str, 74, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = ')' THEN BEGIN kind_str := 'RPAREN'; AddToken(kind_str, 75, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = ';' THEN BEGIN kind_str := 'SEMICOLON'; AddToken(kind_str, 76, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = ',' THEN BEGIN kind_str := 'COMMA'; AddToken(kind_str, 77, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = ':' THEN BEGIN kind_str := 'COLON'; AddToken(kind_str, 78, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE IF ch = '.' THEN BEGIN kind_str := 'DOT'; AddToken(kind_str, 79, lex_str, 3, 0, 0.0, lex_str, start_line, start_col); END
    ELSE
    BEGIN
      { Unrecognized character (e.g. a bare dollar sign outside any comment,
        or a stray close-brace): the Python reference raises LexerError here
        rather than silently accepting it. Match that failure mode with a
        nonzero exit rather than emitting a bogus token. }
      EPrint('Lexer Error: unrecognized character');
      exit(1);
    END;
  END;
END;

PROCEDURE TokenizeBuffer;
VAR
  ch: CHAR;
BEGIN
  WHILE src_pos < src_len DO
  BEGIN
    SkipWhitespace;
    SkipComments;
    IF src_pos >= src_len THEN BREAK;

    ch := ReadBufChar(src_pos);
    IF IsAlpha(ch) THEN
      ScanIdentifier
    ELSE IF IsDigit(ch) THEN
      ScanNumber
    ELSE IF ch = '''' THEN
      ScanString
    ELSE
      ScanSymbol;
  END;
END;

VAR
  empty_str, eof_kind: Str255;

BEGIN
  InitFlags(flags);
  flag_stack_top := 0;
  meta_const_count := 0;
  pending_unroll_set := FALSE;
  pending_leading_count := 0;
  has_last_token := FALSE;
  brace_str[0] := CHR(1);
  brace_str[1] := '}';
  root_array := cJSON_CreateArray;
  cur_line := 1;
  cur_col := 1;
  src_pos := 0;

  ReadSourceInput;

  TokenizeBuffer;

  { Add EOF token at end }
  eof_kind := 'EOF';
  empty_str := '';
  AddToken(eof_kind, 0, empty_str, 0, 0, 0.0, empty_str, cur_line, cur_col);

  json_str := cJSON_Print(root_array);
  puts(json_str);
  free(json_str);
  cJSON_Delete(root_array);
  free(src_buf);
END.
