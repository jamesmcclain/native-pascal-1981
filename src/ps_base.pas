{ Shared-state implementation for the native parser. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
IMPLEMENTATION OF ps_base;

{ C-FFI bindings to libcjson and standard C library routines }
FUNCTION cJSON_Parse(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetObjectItemCaseSensitive(obj: ADRMEM; key: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_DetachItemFromObjectCaseSensitive(obj: ADRMEM; key: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateArray: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateString(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNumber(num: REAL): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateBool(b: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNull: ADRMEM [C]; EXTERN;
PROCEDURE cJSON_AddItemToObject(obj: ADRMEM; key: ADRMEM; item: ADRMEM) [C]; EXTERN;
PROCEDURE cJSON_AddItemToArray(arr: ADRMEM; item: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_Print(item: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE cJSON_Delete(item: ADRMEM) [C]; EXTERN;
PROCEDURE cJSON_DeleteItemFromObject(obj: ADRMEM; key: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_Duplicate(item: ADRMEM; recurse: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_DetachItemFromArray(arr: ADRMEM; which: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_ReplaceItemInObject(obj: ADRMEM; key: ADRMEM; newitem: ADRMEM): CINT [C]; EXTERN;

FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C]; EXTERN;
FUNCTION pas_cjson_int32(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION pas_cjson_int64(item: ADRMEM): CLONG [C]; EXTERN;
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsString(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsTrue(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION puts(str: ADRMEM): CINT [C]; EXTERN;
FUNCTION getchar: CINT [C]; EXTERN;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE free(ptr: ADRMEM) [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;

TYPE
  Token = RECORD
    kind: Str255;
    code: INTEGER32;
    lexeme: Str255;
    value_str: Str255;
    value_int: INTEGER64;
    value_real: REAL;
    value_type: INTEGER32; { 0=null, 1=int, 2=real, 3=str, 4=bool }
    { The integer value is at least 2^63, so value_int holds only its
      WORD64 bit pattern (the lexer's word64 mark). }
    value_word64: BOOLEAN;
    line: INTEGER32;
    col: INTEGER32;
    f_brave, f_debug, f_entry, f_goto, f_indexck, f_initck, f_line, f_list,
    f_mathck, f_nilck, f_ocode, f_rangeck, f_runtime, f_stackck, f_symtab,
    f_warn: BOOLEAN;
    { A one-shot $UNROLL(n) hint stamped by the lexer onto exactly the
      token following the metacommand comment (see lexer.pas). }
    has_unroll: BOOLEAN;
    unroll_val: INTEGER;
    has_leading_comment: BOOLEAN;
    leading_comments: ADRMEM; { see ps_base.inc }
    has_trailing_comment: BOOLEAN;
    trailing_comment: Str255;
    file_name: ADRMEM; { see ps_base.inc }
  END;

  PToken = ^Token;
  TokenBufArray = ARRAY [0..32000] OF Token;
  PTokenBufArray = ^TokenBufArray;

VAR
  tokens_buf: ADRMEM; { heap allocated array of Token }
  num_tokens, pos: INTEGER32;

  { Trivia-relay state for pretty81, private to this unit. A comment queued
    here rides on whichever AST node CreateTriviaNode builds next; a comment
    that was a token's trailing_comment attaches straight onto the most
    recently created node instead, mirroring how the lexer attaches a
    trailing comment straight onto the most recently emitted token
    (lexer.pas RecordComment). }
  pending_leading: ARRAY [1..32] OF Str255;
  pending_leading_count: INTEGER;
  last_created_node: ADRMEM;
  { The node RelayTokenTrivia most recently wrote a trailing_comment onto,
    or NIL. PinTrailingCommentTarget moves the field from here to its own
    argument, since RelayTokenTrivia commits a trailing comment onto
    whatever leaf node was current at token-consumption time -- often
    deep inside an item still being parsed -- not onto the item as a
    whole. }
  last_trailing_target: ADRMEM;

{ ===================== recursion-depth ceilings ======================

  Recursive descent is unbounded by construction: a source file can nest
  expressions or statements as deeply as it likes, and each level costs a
  real stack frame. Without a ceiling the only limit is the OS stack, and
  exceeding it is a segfault with no diagnostic -- which is what used to
  make callers of this parser wrap it in `ulimit -s unlimited`.

  The vintage compiler bounded the same thing and said so: "Expression too
  complex ... Try breaking up expression with intermediate value assigns"
  and "Identifier scopes nested too deeply" are both documented fatal
  conditions in the Aug-1981 manual. So a ceiling here is the period-correct
  behavior, not a concession.

  Sizing. The two recursion cycles cost very different amounts of stack per
  level, so they get separate counters rather than one shared budget:

    expression  ParseExpression -> ParseSimpleExpression -> ParseTerm ->
                ParseFactor -> ParseExpression, about 37KB per level
    statement   ParseStatement -> ParseStatement (ELSE branches, loop and
                CASE bodies), about 7.6KB per level
    type        ParseType -> ParseType (pointer, array, file, and record
                members), about 40KB per level

  Each ceiling stays comfortably inside a default 8MB stack, so the parser
  reaches the ceiling first and prints a message. Real code is nowhere near
  the limits: the five self-hosting sources need only a small fraction of
  the available stack.

  All figures assume the stage is built optimized (scripts/build-native-stage.sh
  passes -O1). Unoptimized, every by-value Str255 argument gets its own spill
  slot and a level costs roughly 8x more.

  The reference compiler enforces the same two ceilings, at the same values,
  on the same two cycles, so the two compilers accept the same language. It
  cannot share these constants -- this file is Pascal -- so a test asserts the
  two definitions agree and that both parsers accept and reject at exactly the
  same depth. }

CONST
  MAX_EXPR_DEPTH = 64;
  MAX_STMT_DEPTH = 256;
  MAX_TYPE_DEPTH = 128;

VAR
  expr_depth, stmt_depth, type_depth: INTEGER;

FUNCTION ReadBoolFlag(flags_json: ADRMEM; key_str: Str255): BOOLEAN;
VAR
  item: ADRMEM;
BEGIN
  IF flags_json = NIL THEN
    ReadBoolFlag := FALSE
  ELSE
  BEGIN
    item := cJSON_GetObjectItemCaseSensitive(flags_json, MakeCStr(key_str));
    IF item = NIL THEN
      ReadBoolFlag := FALSE
    ELSE
      ReadBoolFlag := cJSON_IsTrue(item) <> 0;
  END;
END;

PROCEDURE ReadInputAndParseTokens;
VAR
  raw_input, old_buf: ADRMEM;
  cap, len, i: INTEGER32;
  input_ch, tok_count, res_c: CINT;
  p_in, p_out, p_in_base, p_out_base: ^CHAR;
  json_root, item, field, val_obj, val_str_ptr, base_ptr, val_ptr: ADRMEM;
  k_kind, k_code, k_lex, k_val, k_line, k_col, k_flags: ADRMEM;
  k_val_type, k_unroll, k_leading, k_trailing, k_file: ADRMEM;
  last_file_ptr: ADRMEM;
  file_text, last_file_text: Str255;
  flags_obj: ADRMEM;
  empty_s, fieldName, kind_val: Str255;
  out_i: INTEGER32;
  p_tok: PToken;
  p_tok_arr: PTokenBufArray;
  tok_elem: ADRMEM;
  p_adrmem_off: ^ADRMEM;
  p_real_off: ^REAL;
  comments_arr: ADRMEM;
BEGIN
  pending_leading_count := 0;
  last_created_node := NIL;
  last_trailing_target := NIL;
  cap := 32000;
  raw_input := malloc(cap);
  len := 0;
  input_ch := getchar;
  WHILE input_ch <> -1 DO
  BEGIN
    IF len >= cap THEN
    BEGIN
      old_buf := raw_input;
      cap := cap * 2;
      raw_input := malloc(cap);
      FOR i := 0 TO len - 1 DO
      BEGIN
        p_in_base := old_buf;
        p_out_base := raw_input;
        p_in := p_in_base + i;
        p_out := p_out_base + i;
        p_out^ := p_in^;
      END;
      free(old_buf);
    END;
    p_in_base := raw_input;
    p_in := p_in_base + len;
    { getchar's CINT result is always 0..255 here (the WHILE guard above
      excludes -1), but CHR wants a plain INTEGER and the language has no
      implicit CINT/INTEGER32 -> INTEGER narrowing; RETYPE makes the
      deliberate truncation explicit. }
    p_in^ := CHR(RETYPE(INTEGER, input_ch));
    len := len + 1;
    input_ch := getchar;
  END;
  
  { Null terminate raw_input }
  p_in_base := raw_input;
  p_in := p_in_base + len;
  p_in^ := CHR(0);

  { The driver runs every stage concurrently, so a stage after a failed one
    reads empty input. The failed stage has already reported; fail without
    adding a second, misleading diagnostic (as jsonutil's ReadAllStdin). }
  IF len = 0 THEN
  BEGIN
    free(raw_input);
    exit(1);
  END;

  json_root := cJSON_Parse(raw_input);
  free(raw_input);

  IF json_root = NIL THEN
  BEGIN
    EPrint('Error: Failed to parse input token JSON');
    exit(1);
  END;

  tok_count := cJSON_GetArraySize(json_root);
  num_tokens := tok_count;
  tokens_buf := malloc(num_tokens * SIZEOF(Token));

  fieldName := 'kind'; k_kind := MakeCStr(fieldName);
  fieldName := 'code'; k_code := MakeCStr(fieldName);
  fieldName := 'lexeme'; k_lex := MakeCStr(fieldName);
  fieldName := 'value'; k_val := MakeCStr(fieldName);
  fieldName := 'line'; k_line := MakeCStr(fieldName);
  fieldName := 'column'; k_col := MakeCStr(fieldName);
  fieldName := 'flags'; k_flags := MakeCStr(fieldName);
  fieldName := 'UNROLL'; k_unroll := MakeCStr(fieldName);
  fieldName := 'leading_comments'; k_leading := MakeCStr(fieldName);
  fieldName := 'trailing_comment'; k_trailing := MakeCStr(fieldName);
  fieldName := 'file'; k_file := MakeCStr(fieldName);
  last_file_ptr := NIL;
  last_file_text := '';

  empty_s := '';
  out_i := 0;

  FOR i := 0 TO num_tokens - 1 DO
  BEGIN
    item := cJSON_GetArrayItem(json_root, i);

    { INCLUDE_DIRECTIVE tokens are a driver-level splicing concern (see
      lexer.pas's TryIncludeDirective) -- by the time tokens reach the
      parser they are always a no-op, exactly like Python parser.py's
      pervasive skip_include_directives() calls throughout the grammar.
      Dropping them here, once, up front achieves the same effect without
      needing a matching call at every one of those ~15 call sites. }
    field := cJSON_GetObjectItemCaseSensitive(item, k_kind);
    IF field <> NIL THEN
      kind_val := CStrToStr255(cJSON_GetStringValue(field))
    ELSE
      kind_val := empty_s;
    IF kind_val = 'INCLUDE_DIRECTIVE' THEN CYCLE;

    p_tok := tokens_buf + (out_i * SIZEOF(Token));
    p_tok^.kind := kind_val;

    field := cJSON_GetObjectItemCaseSensitive(item, k_code);
    IF field <> NIL THEN
      p_tok^.code := RETYPE(INTEGER32, pas_cjson_int32(field))
    ELSE
      p_tok^.code := 0;

    field := cJSON_GetObjectItemCaseSensitive(item, k_lex);
    IF field <> NIL THEN
      p_tok^.lexeme := CStrToStr255(cJSON_GetStringValue(field))
    ELSE
      p_tok^.lexeme := empty_s;

    field := cJSON_GetObjectItemCaseSensitive(item, k_val);
    IF (field <> NIL) AND (cJSON_IsNumber(field) <> 0) THEN
    BEGIN
      p_tok^.value_real := cJSON_GetNumberValue(field);
      { Not TRUNC. TRUNC narrows to this dialect's 16-bit INTEGER, so an
        integer literal above 32767 was lost here -- the lexer read 40000
        and the parser stored -25536, and every later stage saw only the
        wrapped value. That, not any property of the dialect, is why large
        literals did not work. GetInt64, not the number alone: a JSON
        number travels as 15 significant digits, so beyond that only the
        lexer's exact decimal companion field still holds the literal. }
      p_tok^.value_int := GetInt64(item, 'value');
      p_tok^.value_word64 := GetBool(item, 'word64');
      p_tok^.value_str := empty_s;
      p_tok^.value_type := 1;
    END
    ELSE IF (field <> NIL) AND (cJSON_IsString(field) <> 0) THEN
    BEGIN
      p_tok^.value_str := CStrToStr255(cJSON_GetStringValue(field));
      p_tok^.value_int := 0;
      p_tok^.value_word64 := FALSE;
      p_tok^.value_real := 0.0;
      p_tok^.value_type := 3;
    END
    ELSE
    BEGIN
      p_tok^.value_str := empty_s;
      p_tok^.value_int := 0;
      p_tok^.value_word64 := FALSE;
      p_tok^.value_real := 0.0;
      p_tok^.value_type := 0;
    END;

    field := cJSON_GetObjectItemCaseSensitive(item, k_line);
    IF field <> NIL THEN
      p_tok^.line := RETYPE(INTEGER32, pas_cjson_int32(field))
    ELSE
      p_tok^.line := 1;

    field := cJSON_GetObjectItemCaseSensitive(item, k_col);
    { Not TRUNC, same conversion as line above: col is INTEGER32, and the
      column of a source line longer than 32767 characters does not fit the
      16-bit INTEGER TRUNC produces -- it would be poison in every
      diagnostic that prints it. The lexer's own column counter still
      wraps at 16 bits, but the token JSON is a stage interface, not a
      private struct, so this side must not assume the producer stays
      narrow. }
    IF field <> NIL THEN
      p_tok^.col := RETYPE(INTEGER32, pas_cjson_int32(field))
    ELSE
      p_tok^.col := 1;

    field := cJSON_GetObjectItemCaseSensitive(item, k_file);
    p_tok^.file_name := NIL;
    IF field <> NIL THEN
      IF cJSON_IsString(field) <> 0 THEN
      BEGIN
        file_text := CStrToStr255(cJSON_GetStringValue(field));
        IF (last_file_ptr = NIL) OR (file_text <> last_file_text) THEN
        BEGIN
          last_file_ptr := MakeCStr(file_text);
          last_file_text := file_text;
        END;
        p_tok^.file_name := last_file_ptr;
      END;

    flags_obj := cJSON_GetObjectItemCaseSensitive(item, k_flags);
    p_tok^.f_brave := ReadBoolFlag(flags_obj, 'BRAVE');
    p_tok^.f_debug := ReadBoolFlag(flags_obj, 'DEBUG');
    p_tok^.f_entry := ReadBoolFlag(flags_obj, 'ENTRY');
    p_tok^.f_goto := ReadBoolFlag(flags_obj, 'GOTO');
    p_tok^.f_indexck := ReadBoolFlag(flags_obj, 'INDEXCK');
    p_tok^.f_initck := ReadBoolFlag(flags_obj, 'INITCK');
    p_tok^.f_line := ReadBoolFlag(flags_obj, 'LINE');
    p_tok^.f_list := ReadBoolFlag(flags_obj, 'LIST');
    p_tok^.f_mathck := ReadBoolFlag(flags_obj, 'MATHCK');
    p_tok^.f_nilck := ReadBoolFlag(flags_obj, 'NILCK');
    p_tok^.f_ocode := ReadBoolFlag(flags_obj, 'OCODE');
    p_tok^.f_rangeck := ReadBoolFlag(flags_obj, 'RANGECK');
    p_tok^.f_runtime := ReadBoolFlag(flags_obj, 'RUNTIME');
    p_tok^.f_stackck := ReadBoolFlag(flags_obj, 'STACKCK');
    p_tok^.f_symtab := ReadBoolFlag(flags_obj, 'SYMTAB');
    p_tok^.f_warn := ReadBoolFlag(flags_obj, 'WARN');

    field := cJSON_GetObjectItemCaseSensitive(flags_obj, k_unroll);
    IF field <> NIL THEN
    BEGIN
      p_tok^.has_unroll := TRUE;
      p_tok^.unroll_val := TRUNC(cJSON_GetNumberValue(field));
    END
    ELSE
    BEGIN
      p_tok^.has_unroll := FALSE;
      p_tok^.unroll_val := 0;
    END;

    { leading_comments: the lexer's array, one string per comment, kept
      whole (it outlives json_root), so each comment stays its own entry
      however many precede the token. Joining them into one Str255 used to
      cut a long run of comments, and pretty81 then printed the run as one
      line, which the next pass read as one comment: not idempotent. }
    comments_arr := cJSON_DetachItemFromObjectCaseSensitive(item, k_leading);
    p_tok^.has_leading_comment := FALSE;
    IF comments_arr <> NIL THEN
      p_tok^.has_leading_comment := cJSON_GetArraySize(comments_arr) > 0;
    p_tok^.leading_comments := comments_arr;

    field := cJSON_GetObjectItemCaseSensitive(item, k_trailing);
    IF field <> NIL THEN
    BEGIN
      p_tok^.has_trailing_comment := TRUE;
      p_tok^.trailing_comment := CStrToStr255(cJSON_GetStringValue(field));
    END
    ELSE
      p_tok^.has_trailing_comment := FALSE;

    out_i := out_i + 1;
  END;
  num_tokens := out_i;

  cJSON_Delete(json_root);
END;

FUNCTION GetTok(off: INTEGER32): PToken;
VAR
  idx: INTEGER32;
BEGIN
  idx := pos + off;
  IF (idx >= 0) AND (idx < num_tokens) THEN
    GetTok := tokens_buf + (idx * SIZEOF(Token))
  ELSE
  BEGIN
    { Return EOF token static fallback }
    GetTok := tokens_buf + ((num_tokens - 1) * SIZEOF(Token));
  END;
END;

FUNCTION CurKind: Str255;
VAR
  pt: PToken;
  res: Str255;
  res_c: CINT;
BEGIN
  pt := GetTok(0);
  res := pt^.kind;
  CurKind := res;
END;

FUNCTION CurLex: Str255;
VAR
  pt: PToken;
  res: Str255;
BEGIN
  pt := GetTok(0);
  res := pt^.lexeme;
  CurLex := res;
END;

FUNCTION CurValueInt: INTEGER64;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurValueInt := pt^.value_int;
END;

FUNCTION CurValueWord64: BOOLEAN;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurValueWord64 := pt^.value_word64;
END;

FUNCTION CurValueReal: REAL;
{ A REAL_LITERAL's value as the lexer computed it from the whole literal
  text (correctly rounded) and printed it exactly. The parser used to
  re-read the Str255 lexeme digit by digit in REAL arithmetic, which
  rounded at each step: 0.30000000000000004 became 0.3000000000000001. }
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurValueReal := pt^.value_real;
END;

FUNCTION CurValueStr: Str255;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurValueStr := pt^.value_str;
END;

FUNCTION CurIndexCk: BOOLEAN;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurIndexCk := pt^.f_indexck;
END;

FUNCTION CurRangeCk: BOOLEAN;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurRangeCk := pt^.f_rangeck;
END;

FUNCTION CurStackCk: BOOLEAN;
{ STACKCK at the current token: a routine's or unit's snapshot is taken at
  its name token (ParseProcDecl and the unit parsers, ps_decl.pas). }
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurStackCk := pt^.f_stackck;
END;

FUNCTION CurHasUnroll: BOOLEAN;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurHasUnroll := pt^.has_unroll;
END;

FUNCTION CurUnrollVal: INTEGER;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurUnrollVal := pt^.unroll_val;
END;

FUNCTION BuildMetaFlagsNode: ADRMEM;
VAR
  pt: PToken;
  obj: ADRMEM;
BEGIN
  pt := GetTok(0);
  obj := cJSON_CreateObject;
  AddBoolField(obj, 'BRAVE', pt^.f_brave);
  AddBoolField(obj, 'DEBUG', pt^.f_debug);
  AddBoolField(obj, 'ENTRY', pt^.f_entry);
  AddBoolField(obj, 'GOTO', pt^.f_goto);
  AddBoolField(obj, 'INDEXCK', pt^.f_indexck);
  AddBoolField(obj, 'INITCK', pt^.f_initck);
  AddBoolField(obj, 'LINE', pt^.f_line);
  AddBoolField(obj, 'LIST', pt^.f_list);
  AddBoolField(obj, 'MATHCK', pt^.f_mathck);
  AddBoolField(obj, 'NILCK', pt^.f_nilck);
  AddBoolField(obj, 'OCODE', pt^.f_ocode);
  AddBoolField(obj, 'RANGECK', pt^.f_rangeck);
  AddBoolField(obj, 'RUNTIME', pt^.f_runtime);
  AddBoolField(obj, 'STACKCK', pt^.f_stackck);
  AddBoolField(obj, 'SYMTAB', pt^.f_symtab);
  AddBoolField(obj, 'WARN', pt^.f_warn);
  BuildMetaFlagsNode := obj;
END;

FUNCTION CurLabelKey: INTEGER;
{ A numeric label's key: the 16-bit bit pattern of the INTEGER_LITERAL's
  value, so high-bit labels (32768..65535) are kept modulo 65536. It comes
  from the token's value, not its Str255 lexeme, which stops at 255
  characters: a label written with 300 leading zeros keeps its number. }
VAR
  v: INTEGER64;
BEGIN
  v := CurValueInt MOD 65536;
  IF v < 0 THEN v := v + 65536;
  IF v >= 32768 THEN v := v - 65536;
  CurLabelKey := RETYPE(INTEGER, v);
END;

FUNCTION StringEqual(s1, s2: Str255): BOOLEAN;
VAR
  len1, len2, i: INTEGER;
  eq: BOOLEAN;
BEGIN
  len1 := ORD(s1[0]);
  len2 := ORD(s2[0]);
  IF len1 <> len2 THEN
    StringEqual := FALSE
  ELSE
  BEGIN
    eq := TRUE;
    FOR i := 1 TO len1 DO
      IF s1[i] <> s2[i] THEN eq := FALSE;
    StringEqual := eq;
  END;
END;

FUNCTION UpperStr(s: Str255): Str255;
VAR
  i, len: INTEGER;
  res: Str255;
  ch: CHAR;
BEGIN
  len := ORD(s[0]);
  res[0] := CHR(len);
  FOR i := 1 TO len DO
  BEGIN
    ch := s[i];
    IF (ch >= 'a') AND (ch <= 'z') THEN
      res[i] := CHR(ORD(ch) - 32)
    ELSE
      res[i] := ch;
  END;
  UpperStr := res;
END;

PROCEDURE RelayTokenTrivia;
{ Called just before the cursor steps past the current token (from Expect
  and Match, the only two places pos advances), so every token's trivia is
  relayed exactly once regardless of which of the two consumed it. A
  leading comment queues for whichever node CreateTriviaNode builds next; a
  trailing comment attaches straight onto the most recently created node
  when nothing is already queued (mirroring lexer.pas RecordComment), and
  falls back to queuing itself otherwise so it is never silently dropped. }
VAR
  pt: PToken;
  key_ptr, str_ptr: ADRMEM;
  fieldName: Str255;
  ci: INTEGER32;
BEGIN
  pt := GetTok(0);
  IF pt^.has_leading_comment THEN
    FOR ci := 0 TO cJSON_GetArraySize(pt^.leading_comments) - 1 DO
      IF pending_leading_count < 32 THEN
      BEGIN
        pending_leading_count := pending_leading_count + 1;
        pending_leading[pending_leading_count] :=
          CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(pt^.leading_comments, ci)));
      END;
  IF pt^.has_trailing_comment THEN
  BEGIN
    { A node keeps one trailing comment: a second queues for the next node,
      as the lexer does for a second comment after one token. }
    IF (pending_leading_count = 0) AND (last_created_node <> NIL) AND
       (cJSON_GetObjectItemCaseSensitive(last_created_node, MakeCStr('trailing_comment')) = NIL) THEN
    BEGIN
      str_ptr := MakeCStr(pt^.trailing_comment);
      fieldName := 'trailing_comment'; key_ptr := MakeCStr(fieldName);
      cJSON_AddItemToObject(last_created_node, key_ptr, cJSON_CreateString(str_ptr));
      { After a separator the comment is final: the item before it is
        already complete (pinned), and the next item's pin must not take
        it. Otherwise the enclosing item's pin may still claim it. }
      IF pt^.kind = 'SEMICOLON' THEN
        last_trailing_target := NIL
      ELSE
        last_trailing_target := last_created_node;
    END
    ELSE IF pending_leading_count < 32 THEN
    BEGIN
      pending_leading_count := pending_leading_count + 1;
      pending_leading[pending_leading_count] := pt^.trailing_comment;
    END;
  END;
END;

FUNCTION PsIntText(n: INTEGER32): Str255;
{ Decimal text of a nonnegative line or column number. }
VAR
  rev, text: Str255;
  k: INTEGER;
BEGIN
  rev[0] := CHR(1);
  rev[1] := CHR(ORD('0') + n MOD 10);
  n := n DIV 10;
  WHILE n > 0 DO
  BEGIN
    rev[0] := CHR(ORD(rev[0]) + 1);
    rev[ORD(rev[0])] := CHR(ORD('0') + n MOD 10);
    n := n DIV 10;
  END;
  text[0] := rev[0];
  FOR k := 1 TO ORD(rev[0]) DO text[k] := rev[ORD(rev[0]) + 1 - k];
  PsIntText := text;
END;

PROCEDURE PsAppendText(VAR s: Str255; t: Str255);
{ Append, silently stopping at the 255-character capacity. }
VAR
  i, len: INTEGER;
BEGIN
  FOR i := 1 TO ORD(t[0]) DO
  BEGIN
    len := ORD(s[0]);
    IF len < 255 THEN
    BEGIN
      s[len + 1] := t[i];
      s[0] := CHR(len + 1);
    END;
  END;
END;

PROCEDURE ParseFail(msg: Str255);
{ Report a parser error at the current token and stop: msg followed by the
  located-diagnostic suffix every stage uses, ` at line L column C', plus
  ` of file NAME' for a token from an $INCLUDEd file. A report of several
  lines prints the others first and passes its last line here. }
VAR
  tok: PToken;
BEGIN
  tok := GetTok(0);
  IF (tok^.line > 0) AND (tok^.col > 0) THEN
  BEGIN
    PsAppendText(msg, ' at line ');
    PsAppendText(msg, PsIntText(tok^.line));
    PsAppendText(msg, ' column ');
    PsAppendText(msg, PsIntText(tok^.col));
    IF tok^.file_name <> NIL THEN
    BEGIN
      PsAppendText(msg, ' of file ');
      PsAppendText(msg, CStrToStr255(tok^.file_name));
    END;
  END;
  EPrint(msg);
  exit(1);
END;

PROCEDURE Expect(k: Str255);
VAR
  err_msg, ck, target_k: Str255;
  res_c: CINT;
BEGIN
  target_k := k;
  ck := CurKind;
  IF StringEqual(ck, target_k) THEN
  BEGIN
    RelayTokenTrivia;
    pos := pos + 1;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: Expected token match failed. Expected:');
    EPrint(target_k);
    EPrint('Got:');
    ParseFail(ck);
  END;
END;

FUNCTION Match(k: Str255): BOOLEAN;
VAR
  target_k: Str255;
BEGIN
  target_k := k;
  IF StringEqual(CurKind, target_k) THEN
  BEGIN
    RelayTokenTrivia;
    pos := pos + 1;
    Match := TRUE;
  END
  ELSE
    Match := FALSE;
END;

FUNCTION TokLocation(tok: PToken): ADRMEM;
{ A token's line and column, plus its `file' when it came from an included
  file, for a node's `location', `op_location' or `read_location' field. A
  primary-file location has no `file' field. }
VAR
  location, key_ptr: ADRMEM;
  fieldName: Str255;
BEGIN
  location := cJSON_CreateObject;
  AddIntField(location, 'line', tok^.line);
  AddIntField(location, 'column', tok^.col);
  IF tok^.file_name <> NIL THEN
  BEGIN
    fieldName := 'file'; key_ptr := MakeCStr(fieldName);
    cJSON_AddItemToObject(location, key_ptr, cJSON_CreateString(tok^.file_name));
  END;
  TokLocation := location;
END;

FUNCTION CurLocation: ADRMEM;
{ The current token's location (TokLocation). }
BEGIN
  CurLocation := TokLocation(GetTok(0));
END;

FUNCTION CreateTriviaNode(type_name: Str255): ADRMEM;
{ A node that takes the leading comments queued so far (pending_leading). }
VAR
  node, comments_arr: ADRMEM;
  key_ptr: ADRMEM;
  fieldName: Str255;
  i: INTEGER;
BEGIN
  node := CreateNode(type_name);
  IF pending_leading_count > 0 THEN
  BEGIN
    comments_arr := cJSON_CreateArray;
    FOR i := 1 TO pending_leading_count DO
      cJSON_AddItemToArray(comments_arr, cJSON_CreateString(MakeCStr(pending_leading[i])));
    fieldName := 'leading_comments'; key_ptr := MakeCStr(fieldName);
    cJSON_AddItemToObject(node, key_ptr, comments_arr);
    pending_leading_count := 0;
  END;
  last_created_node := node;
  CreateTriviaNode := node;
END;

FUNCTION CreateLeadTriviaNode(type_name: Str255): ADRMEM;
{ CreateTriviaNode for a node built before its first token is consumed (an
  assignment, a call, RETURN, a labelled or empty statement, a CASE
  element): it also takes
  that token's leading comments, now. They used to ride on whatever trivia
  node came next, often in another statement, and moved again on every
  pretty81 pass. }
VAR
  pt: PToken;
  ci: INTEGER32;
BEGIN
  pt := GetTok(0);
  IF pt^.has_leading_comment THEN
  BEGIN
    FOR ci := 0 TO cJSON_GetArraySize(pt^.leading_comments) - 1 DO
      IF pending_leading_count < 32 THEN
      BEGIN
        pending_leading_count := pending_leading_count + 1;
        pending_leading[pending_leading_count] :=
          CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(pt^.leading_comments, ci)));
      END;
    pt^.has_leading_comment := FALSE;
  END;
  CreateLeadTriviaNode := CreateTriviaNode(type_name);
END;

{ Re-point trailing-comment attachment at an enclosing node whose children
  are already fully parsed. Called by a list-parsing loop (statement list,
  decl section, case element, ...) right after it finishes one item and
  before it checks for a following separator: without this, a comment
  trailing the whole item -- e.g. an assignment followed by a same-line
  remark -- would attach to whatever inner node, like a call expression on
  the right-hand side, happened to be built last during that item's own
  parsing, instead of to the item itself. }
PROCEDURE PinTrailingCommentTarget(node: ADRMEM);
{ The comment then belongs to this item: last_trailing_target is cleared,
  so the next item's pin cannot carry it further. It used to stay set, and
  each later item of the list took the comment over in turn, so a comment
  drifted to the end of its list (and further on every pretty81 pass). A
  node that already has a trailing comment keeps it. }
VAR
  text_item: ADRMEM;
  comment_text: Str255;
BEGIN
  IF (last_trailing_target <> NIL) AND (last_trailing_target <> node) AND
     (cJSON_GetObjectItemCaseSensitive(node, MakeCStr('trailing_comment')) = NIL) THEN
  BEGIN
    text_item := cJSON_GetObjectItemCaseSensitive(last_trailing_target, MakeCStr('trailing_comment'));
    IF text_item <> NIL THEN
    BEGIN
      comment_text := CStrToStr255(cJSON_GetStringValue(text_item));
      cJSON_DeleteItemFromObject(last_trailing_target, MakeCStr('trailing_comment'));
      cJSON_AddItemToObject(node, MakeCStr('trailing_comment'), cJSON_CreateString(MakeCStr(comment_text)));
    END;
  END;
  last_trailing_target := NIL;
  last_created_node := node;
END;

{ Enter/leave one level of the expression recursion cycle. Every increment
  must be paired with a decrement on every path out of the guarded routine,
  so guard only routines with a single fall-through exit. }
PROCEDURE EnterExprLevel;
VAR
  res_c: CINT;
BEGIN
  expr_depth := expr_depth + 1;
  IF expr_depth > MAX_EXPR_DEPTH THEN
  BEGIN
    ParseFail('Parser Error: expression too complex (nesting deeper than 64); try breaking it up with intermediate value assigns');
  END;
END;

PROCEDURE LeaveExprLevel;
BEGIN
  expr_depth := expr_depth - 1;
END;

PROCEDURE EnterStmtLevel;
VAR
  res_c: CINT;
BEGIN
  stmt_depth := stmt_depth + 1;
  IF stmt_depth > MAX_STMT_DEPTH THEN
  BEGIN
    ParseFail('Parser Error: statements nested too deeply (deeper than 256); try splitting the routine up');
  END;
END;

PROCEDURE LeaveStmtLevel;
BEGIN
  stmt_depth := stmt_depth - 1;
END;

PROCEDURE EnterTypeLevel;
VAR
  res_c: CINT;
BEGIN
  type_depth := type_depth + 1;
  IF type_depth > MAX_TYPE_DEPTH THEN
  BEGIN
    ParseFail('Parser Error: type nested too deeply (deeper than 128); try defining intermediate named types');
  END;
END;

PROCEDURE LeaveTypeLevel;
BEGIN
  type_depth := type_depth - 1;
END;

BEGIN
END.
