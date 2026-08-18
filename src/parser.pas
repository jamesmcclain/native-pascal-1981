{ Pascal-1981 Native Parser implementation in extended IBM Pascal 2.0 dialect.
  Consumes JSON token stream from standard input (produced by pascal1981-lex)
  and outputs JSON AST stream on standard output (consumed by pascal1981-codegen). }

(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_parse(input, output);

USES jsonutil;

{ C-FFI bindings to libcjson and standard C library routines }
FUNCTION cJSON_Parse(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetObjectItem(obj: ADRMEM; key: ADRMEM): ADRMEM [C]; EXTERN;
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
FUNCTION cJSON_Duplicate(item: ADRMEM; recurse: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_DetachItemFromArray(arr: ADRMEM; which: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_ReplaceItemInObject(obj: ADRMEM; key: ADRMEM; newitem: ADRMEM): CINT [C]; EXTERN;

FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C]; EXTERN;
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
    value_int: INTEGER32;
    value_real: REAL;
    value_type: INTEGER32; { 0=null, 1=int, 2=real, 3=str, 4=bool }
    line: INTEGER32;
    col: INTEGER32;
    f_brave, f_debug, f_entry, f_goto, f_indexck, f_initck, f_line, f_list,
    f_mathck, f_nilck, f_ocode, f_rangeck, f_runtime, f_stackck, f_symtab,
    f_warn: BOOLEAN;
    { A one-shot $UNROLL(n) hint stamped by the lexer onto exactly the
      token following the metacommand comment (see lexer.pas). }
    has_unroll: BOOLEAN;
    unroll_val: INTEGER;
  END;

  PToken = ^Token;
  TokenBufArray = ARRAY [0..32000] OF Token;
  PTokenBufArray = ^TokenBufArray;

VAR
  tokens_buf: ADRMEM; { heap allocated array of Token }
  num_tokens, pos: INTEGER32;

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

  At the ceilings below the worst case is 64*37KB + 256*7.6KB, about 4.3MB
  -- comfortably inside a default 8MB stack, so the ceiling is what is
  reached first and it is reached with a message. Real code is nowhere near
  either: the deepest of the five self-hosting sources needs about 512KB.

  Both figures assume the stage is built optimized (scripts/build-native-stage.sh
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

VAR
  expr_depth, stmt_depth: INTEGER;

FUNCTION ReadBoolFlag(flags_json: ADRMEM; key_str: Str255): BOOLEAN;
VAR
  item: ADRMEM;
BEGIN
  IF flags_json = NIL THEN
    ReadBoolFlag := FALSE
  ELSE
  BEGIN
    item := cJSON_GetObjectItem(flags_json, MakeCStr(key_str));
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
  k_val_type, k_unroll: ADRMEM;
  flags_obj: ADRMEM;
  empty_s, fieldName, kind_val: Str255;
  out_i: INTEGER32;
  p_tok: PToken;
  p_tok_arr: PTokenBufArray;
  tok_elem: ADRMEM;
  p_adrmem_off: ^ADRMEM;
  p_real_off: ^REAL;
BEGIN
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

  json_root := cJSON_Parse(raw_input);
  free(raw_input);

  IF json_root = NIL THEN
  BEGIN
    res_c := puts(MakeCStr('Error: Failed to parse input token JSON'));
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
    field := cJSON_GetObjectItem(item, k_kind);
    IF field <> NIL THEN
      kind_val := CStrToStr255(cJSON_GetStringValue(field))
    ELSE
      kind_val := empty_s;
    IF kind_val = 'INCLUDE_DIRECTIVE' THEN CYCLE;

    p_tok := tokens_buf + (out_i * SIZEOF(Token));
    p_tok^.kind := kind_val;

    field := cJSON_GetObjectItem(item, k_code);
    IF field <> NIL THEN
      p_tok^.code := TRUNC(cJSON_GetNumberValue(field))
    ELSE
      p_tok^.code := 0;

    field := cJSON_GetObjectItem(item, k_lex);
    IF field <> NIL THEN
      p_tok^.lexeme := CStrToStr255(cJSON_GetStringValue(field))
    ELSE
      p_tok^.lexeme := empty_s;

    field := cJSON_GetObjectItem(item, k_val);
    IF (field <> NIL) AND (cJSON_IsNumber(field) <> 0) THEN
    BEGIN
      p_tok^.value_real := cJSON_GetNumberValue(field);
      p_tok^.value_int := TRUNC(p_tok^.value_real);
      p_tok^.value_str := empty_s;
      p_tok^.value_type := 1;
    END
    ELSE IF (field <> NIL) AND (cJSON_IsString(field) <> 0) THEN
    BEGIN
      p_tok^.value_str := CStrToStr255(cJSON_GetStringValue(field));
      p_tok^.value_int := 0;
      p_tok^.value_real := 0.0;
      p_tok^.value_type := 3;
    END
    ELSE
    BEGIN
      p_tok^.value_str := empty_s;
      p_tok^.value_int := 0;
      p_tok^.value_real := 0.0;
      p_tok^.value_type := 0;
    END;

    field := cJSON_GetObjectItem(item, k_line);
    IF field <> NIL THEN
      p_tok^.line := TRUNC(cJSON_GetNumberValue(field))
    ELSE
      p_tok^.line := 1;

    field := cJSON_GetObjectItem(item, k_col);
    IF field <> NIL THEN
      p_tok^.col := TRUNC(cJSON_GetNumberValue(field))
    ELSE
      p_tok^.col := 1;

    flags_obj := cJSON_GetObjectItem(item, k_flags);
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

    field := cJSON_GetObjectItem(flags_obj, k_unroll);
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

FUNCTION CurValueInt: INTEGER32;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurValueInt := pt^.value_int;
END;

FUNCTION CurValueReal: REAL;
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

FUNCTION CurRangeCk: BOOLEAN;
VAR
  pt: PToken;
BEGIN
  pt := GetTok(0);
  CurRangeCk := pt^.f_rangeck;
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

FUNCTION StrToIntVal(s: Str255): INTEGER;
VAR
  i, len, val: INTEGER;
  neg: BOOLEAN;
BEGIN
  len := ORD(s[0]);
  val := 0;
  neg := FALSE;
  i := 1;
  IF (len >= 1) AND (s[1] = '-') THEN
  BEGIN
    neg := TRUE;
    i := 2;
  END;
  WHILE i <= len DO
  BEGIN
    IF (s[i] >= '0') AND (s[i] <= '9') THEN
      val := val * 10 + (ORD(s[i]) - ORD('0'));
    i := i + 1;
  END;
  IF neg THEN val := -val;
  StrToIntVal := val;
END;

FUNCTION StrToRealVal(s: Str255): REAL;
VAR
  i, len, exp_val: INTEGER;
  int_part, frac_part, frac_scale, result_val, pw: REAL;
  exp_neg: BOOLEAN;
  k: INTEGER;
BEGIN
  len := ORD(s[0]);
  i := 1;
  int_part := 0.0;
  WHILE (i <= len) AND (s[i] >= '0') AND (s[i] <= '9') DO
  BEGIN
    int_part := int_part * 10.0 + (ORD(s[i]) - ORD('0'));
    i := i + 1;
  END;
  frac_part := 0.0;
  frac_scale := 1.0;
  IF (i <= len) AND (s[i] = '.') THEN
  BEGIN
    i := i + 1;
    WHILE (i <= len) AND (s[i] >= '0') AND (s[i] <= '9') DO
    BEGIN
      frac_scale := frac_scale / 10.0;
      frac_part := frac_part + (ORD(s[i]) - ORD('0')) * frac_scale;
      i := i + 1;
    END;
  END;
  exp_val := 0;
  exp_neg := FALSE;
  IF (i <= len) AND ((s[i] = 'E') OR (s[i] = 'e')) THEN
  BEGIN
    i := i + 1;
    IF (i <= len) AND (s[i] = '+') THEN
      i := i + 1
    ELSE IF (i <= len) AND (s[i] = '-') THEN
    BEGIN
      exp_neg := TRUE;
      i := i + 1;
    END;
    WHILE (i <= len) AND (s[i] >= '0') AND (s[i] <= '9') DO
    BEGIN
      exp_val := exp_val * 10 + (ORD(s[i]) - ORD('0'));
      i := i + 1;
    END;
  END;
  result_val := int_part + frac_part;
  pw := 1.0;
  FOR k := 1 TO exp_val DO
    IF exp_neg THEN
      pw := pw / 10.0
    ELSE
      pw := pw * 10.0;
  StrToRealVal := result_val * pw;
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

PROCEDURE Expect(k: Str255);
VAR
  err_msg, ck, target_k: Str255;
  res_c: CINT;
BEGIN
  target_k := k;
  ck := CurKind;
  IF StringEqual(ck, target_k) THEN
  BEGIN
    pos := pos + 1;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: Expected token match failed. Expected:'));
    res_c := puts(MakeCStr(target_k));
    res_c := puts(MakeCStr('Got:'));
    res_c := puts(MakeCStr(ck));
    exit(1);
  END;
END;

FUNCTION Match(k: Str255): BOOLEAN;
VAR
  target_k: Str255;
BEGIN
  target_k := k;
  IF StringEqual(CurKind, target_k) THEN
  BEGIN
    pos := pos + 1;
    Match := TRUE;
  END
  ELSE
    Match := FALSE;
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
    res_c := puts(MakeCStr('Parser Error: expression too complex (nesting deeper than 64); try breaking it up with intermediate value assigns'));
    exit(1);
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
    res_c := puts(MakeCStr('Parser Error: statements nested too deeply (deeper than 256); try splitting the routine up'));
    exit(1);
  END;
END;

PROCEDURE LeaveStmtLevel;
BEGIN
  stmt_depth := stmt_depth - 1;
END;

{ AST Builder Parser Stubs }

FUNCTION ParseExpression: ADRMEM; FORWARD;
FUNCTION ParseBooleanExpression: ADRMEM; FORWARD;
FUNCTION ParseSimpleExpression: ADRMEM; FORWARD;
FUNCTION ParseTerm: ADRMEM; FORWARD;
FUNCTION ParseFactor: ADRMEM; FORWARD;
FUNCTION ParseStatement: ADRMEM; FORWARD;
FUNCTION ParseBlock: ADRMEM; FORWARD;
FUNCTION ParseType: ADRMEM; FORWARD;
FUNCTION ParseConstant: ADRMEM; FORWARD;
FUNCTION ParseCompoundStmt: ADRMEM; FORWARD;
FUNCTION ParseCompoundStmtList: ADRMEM; FORWARD;
FUNCTION ParseIfStmt: ADRMEM; FORWARD;
FUNCTION ParseForStmt: ADRMEM; FORWARD;
FUNCTION ParseWhileStmt: ADRMEM; FORWARD;
FUNCTION ParseRepeatStmt: ADRMEM; FORWARD;
FUNCTION ParseCaseStmt: ADRMEM; FORWARD;
FUNCTION ParseWithStmt: ADRMEM; FORWARD;
FUNCTION ParseProcDecl: ADRMEM; FORWARD;
FUNCTION ParseFuncDecl: ADRMEM; FORWARD;

FUNCTION ParseIdentifier: ADRMEM;
VAR
  node: ADRMEM;
  name: Str255;
BEGIN
  node := CreateNode('Identifier');
  name := CurLex;
  Expect('IDENTIFIER');
  AddStringField(node, 'name', name);
  ParseIdentifier := node;
END;

FUNCTION ParseDesignatorRest(name: Str255): ADRMEM;
VAR
  node, selectors_arr, sel_obj: ADRMEM;
  has_sel: BOOLEAN;
BEGIN
  selectors_arr := cJSON_CreateArray;
  has_sel := FALSE;

  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    has_sel := TRUE;
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'INDEX');
      AddField(sel_obj, 'index_or_field', ParseExpression);
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(selectors_arr, sel_obj);
        sel_obj := CreateNode('Selector');
        AddStringField(sel_obj, 'kind', 'INDEX');
        AddField(sel_obj, 'index_or_field', ParseExpression);
      END;
      Expect('RBRACKET');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE IF CurKind = 'DOT' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'FIELD');
      AddStringField(sel_obj, 'index_or_field', CurLex);
      Expect('IDENTIFIER');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE IF CurKind = 'POINTER' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'DEREF');
      AddNullField(sel_obj, 'index_or_field');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END;
  END;

  IF has_sel THEN
  BEGIN
    node := CreateNode('Designator');
    AddStringField(node, 'name', name);
    AddField(node, 'selectors', selectors_arr);
    ParseDesignatorRest := node;
  END
  ELSE
  BEGIN
    node := CreateNode('Identifier');
    AddStringField(node, 'name', name);
    ParseDesignatorRest := node;
  END;
END;

FUNCTION ParseDesignator: ADRMEM;
VAR
  node, selectors_arr, sel_obj: ADRMEM;
  name: Str255;
BEGIN
  node := CreateNode('Designator');
  name := CurLex;
  Expect('IDENTIFIER');
  AddStringField(node, 'name', name);
  selectors_arr := cJSON_CreateArray;

  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'INDEX');
      AddField(sel_obj, 'index_or_field', ParseExpression);
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(selectors_arr, sel_obj);
        sel_obj := CreateNode('Selector');
        AddStringField(sel_obj, 'kind', 'INDEX');
        AddField(sel_obj, 'index_or_field', ParseExpression);
      END;
      Expect('RBRACKET');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE IF CurKind = 'DOT' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'FIELD');
      AddStringField(sel_obj, 'index_or_field', CurLex);
      Expect('IDENTIFIER');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE IF CurKind = 'POINTER' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'DEREF');
      AddNullField(sel_obj, 'index_or_field');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END;
  END;

  AddField(node, 'selectors', selectors_arr);
  ParseDesignator := node;
END;

FUNCTION NextKind: Str255;
VAR
  pt: PToken;
  res: Str255;
BEGIN
  pt := GetTok(1);
  res := pt^.kind;
  NextKind := res;
END;

FUNCTION MakeBinOp(op_str: Str255; left, right: ADRMEM): ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateNode('BinOp');
  AddStringField(node, 'op', op_str);
  AddField(node, 'left', left);
  AddField(node, 'right', right);
  MakeBinOp := node;
END;

FUNCTION ParseActualParameterList: ADRMEM;
VAR
  args_arr: ADRMEM;
BEGIN
  args_arr := cJSON_CreateArray;
  IF CurKind <> 'RPAREN' THEN
  BEGIN
    cJSON_AddItemToArray(args_arr, ParseExpression);
    WHILE Match('COMMA') DO
      cJSON_AddItemToArray(args_arr, ParseExpression);
  END;
  ParseActualParameterList := args_arr;
END;

FUNCTION ParseIdentListArr: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  cJSON_AddItemToArray(arr, cJSON_CreateString(MakeCStr(CurLex)));
  Expect('IDENTIFIER');
  WHILE Match('COMMA') DO
  BEGIN
    cJSON_AddItemToArray(arr, cJSON_CreateString(MakeCStr(CurLex)));
    Expect('IDENTIFIER');
  END;
  ParseIdentListArr := arr;
END;

FUNCTION ParseConstant: ADRMEM;
VAR
  node, args_arr_const: ADRMEM;
  val_str: Str255;
  sign_neg: BOOLEAN;
  res_c: CINT;
BEGIN
  { Mirrors parser.py's parse_constant precedence exactly: an unsigned
    literal/identifier is tried first (no sign consumed here), and a leading
    +/- sign is only legal directly before INTEGER_LITERAL/REAL_LITERAL --
    e.g. -'A' must be rejected, not silently accepted. }
  IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    node := CreateNode('IntLiteral');
    { CurValueInt returns INTEGER32 (it holds a literal's full folded value),
      but AddIntField's value param is a plain INTEGER and the language has
      no implicit INTEGER32 -> INTEGER narrowing; RETYPE makes the
      deliberate truncation explicit. }
    AddIntField(node, 'value', RETYPE(INTEGER, CurValueInt()));
    Expect('INTEGER_LITERAL');
    ParseConstant := node;
  END
  ELSE IF CurKind = 'REAL_LITERAL' THEN
  BEGIN
    node := CreateNode('RealLiteral');
    val_str := CurLex;
    Expect('REAL_LITERAL');
    AddRealField(node, 'value', StrToRealVal(val_str));
    ParseConstant := node;
  END
  ELSE IF CurKind = 'CHAR_LITERAL' THEN
  BEGIN
    node := CreateNode('CharLiteral');
    val_str := CurValueStr;
    Expect('CHAR_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseConstant := node;
  END
  ELSE IF CurKind = 'STRING_LITERAL' THEN
  BEGIN
    node := CreateNode('StringLiteral');
    val_str := CurLex;
    Expect('STRING_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseConstant := node;
  END
  ELSE IF CurKind = 'BOOLEAN_LITERAL' THEN
  BEGIN
    node := CreateNode('BoolLiteral');
    val_str := CurLex;
    Expect('BOOLEAN_LITERAL');
    AddBoolField(node, 'value', StringEqual(UpperStr(val_str), 'TRUE'));
    ParseConstant := node;
  END
  ELSE IF CurKind = 'NIL' THEN
  BEGIN
    pos := pos + 1;
    ParseConstant := CreateNode('NilLiteral');
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    val_str := CurLex;
    Expect('IDENTIFIER');
    IF (StringEqual(UpperStr(val_str), 'WRD') OR StringEqual(UpperStr(val_str), 'BYWORD')) AND
       (CurKind = 'LPAREN') THEN
    BEGIN
      pos := pos + 1;
      node := CreateNode('FuncCall');
      AddStringField(node, 'name', val_str);
      args_arr_const := cJSON_CreateArray;
      cJSON_AddItemToArray(args_arr_const, ParseConstant());
      WHILE CurKind = 'COMMA' DO
      BEGIN
        pos := pos + 1;
        cJSON_AddItemToArray(args_arr_const, ParseConstant());
      END;
      Expect('RPAREN');
      AddField(node, 'args', args_arr_const);
      ParseConstant := node;
    END
    ELSE
    BEGIN
      node := CreateNode('Identifier');
      AddStringField(node, 'name', val_str);
      ParseConstant := node;
    END;
  END
  ELSE IF (CurKind = 'PLUS') OR (CurKind = 'MINUS') THEN
  BEGIN
    sign_neg := (CurKind = 'MINUS');
    pos := pos + 1;
    IF CurKind = 'INTEGER_LITERAL' THEN
    BEGIN
      node := CreateNode('IntLiteral');
      { CurValueInt returns INTEGER32 (it holds a literal's full folded
        value), but AddIntField's value param is a plain INTEGER and the
        language has no implicit INTEGER32 -> INTEGER narrowing; RETYPE
        makes the deliberate truncation explicit. }
      IF sign_neg THEN
        AddIntField(node, 'value', -RETYPE(INTEGER, CurValueInt()))
      ELSE
        AddIntField(node, 'value', RETYPE(INTEGER, CurValueInt()));
      Expect('INTEGER_LITERAL');
      ParseConstant := node;
    END
    ELSE IF CurKind = 'REAL_LITERAL' THEN
    BEGIN
      node := CreateNode('RealLiteral');
      val_str := CurLex;
      Expect('REAL_LITERAL');
      IF sign_neg THEN
        AddRealField(node, 'value', -StrToRealVal(val_str))
      ELSE
        AddRealField(node, 'value', StrToRealVal(val_str));
      ParseConstant := node;
    END
    ELSE
    BEGIN
      res_c := puts(MakeCStr('Parser Error: expected numeric constant'));
      exit(1);
    END;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: expected constant'));
    exit(1);
  END;
END;

FUNCTION ParseSetElement: ADRMEM;
VAR
  e, high, node: ADRMEM;
BEGIN
  e := ParseExpression;
  IF Match('RANGE') THEN
  BEGIN
    high := ParseExpression;
    node := CreateNode('RangeExpr');
    AddField(node, 'low', e);
    AddField(node, 'high', high);
    ParseSetElement := node;
  END
  ELSE
    ParseSetElement := e;
END;

FUNCTION ParseFactor: ADRMEM;
VAR
  node, expr, args_arr, elements_arr: ADRMEM;
  val_str, name, kop: Str255;
  res_c: CINT;
BEGIN
  IF CurKind = 'NOT' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('UnaryOp');
    AddStringField(node, 'op', 'NOT');
    AddField(node, 'operand', ParseFactor);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    node := CreateNode('IntLiteral');
    { CurValueInt returns INTEGER32 (it holds a literal's full folded value),
      but AddIntField's value param is a plain INTEGER and the language has
      no implicit INTEGER32 -> INTEGER narrowing; RETYPE makes the
      deliberate truncation explicit. }
    AddIntField(node, 'value', RETYPE(INTEGER, CurValueInt()));
    Expect('INTEGER_LITERAL');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'REAL_LITERAL' THEN
  BEGIN
    node := CreateNode('RealLiteral');
    val_str := CurLex;
    Expect('REAL_LITERAL');
    AddRealField(node, 'value', StrToRealVal(val_str));
    ParseFactor := node;
  END
  ELSE IF CurKind = 'CHAR_LITERAL' THEN
  BEGIN
    node := CreateNode('CharLiteral');
    val_str := CurValueStr;
    Expect('CHAR_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'STRING_LITERAL' THEN
  BEGIN
    node := CreateNode('StringLiteral');
    val_str := CurLex;
    Expect('STRING_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'BOOLEAN_LITERAL' THEN
  BEGIN
    node := CreateNode('BoolLiteral');
    val_str := CurLex;
    Expect('BOOLEAN_LITERAL');
    AddBoolField(node, 'value', StringEqual(val_str, 'TRUE') OR StringEqual(val_str, 'true'));
    ParseFactor := node;
  END
  ELSE IF CurKind = 'NIL' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('NilLiteral');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    name := CurLex;
    IF (name = 'RETYPE') AND (NextKind = 'LPAREN') THEN
    BEGIN
      pos := pos + 2;
      val_str := CurLex;
      Expect('IDENTIFIER');
      Expect('COMMA');
      expr := ParseExpression;
      Expect('RPAREN');
      node := CreateNode('RetypeExpr');
      AddStringField(node, 'type_id', val_str);
      AddField(node, 'expr', expr);
      AddField(node, 'selectors', cJSON_CreateArray);
      ParseFactor := node;
    END
    ELSE IF NextKind = 'LPAREN' THEN
    BEGIN
      pos := pos + 2;
      IF CurKind <> 'RPAREN' THEN
        args_arr := ParseActualParameterList
      ELSE
        args_arr := cJSON_CreateArray;
      Expect('RPAREN');
      node := CreateNode('FuncCall');
      AddStringField(node, 'name', name);
      AddField(node, 'args', args_arr);
      ParseFactor := node;
    END
    ELSE
    BEGIN
      pos := pos + 1;
      ParseFactor := ParseDesignatorRest(name);
    END;
  END
  ELSE IF CurKind = 'LPAREN' THEN
  BEGIN
    Expect('LPAREN');
    expr := ParseExpression;
    Expect('RPAREN');
    ParseFactor := expr;
  END
  ELSE IF CurKind = 'LBRACKET' THEN
  BEGIN
    pos := pos + 1;
    elements_arr := cJSON_CreateArray;
    IF CurKind <> 'RBRACKET' THEN
    BEGIN
      cJSON_AddItemToArray(elements_arr, ParseSetElement);
      WHILE Match('COMMA') DO
        cJSON_AddItemToArray(elements_arr, ParseSetElement);
    END;
    Expect('RBRACKET');
    node := CreateNode('SetConstructor');
    AddField(node, 'elements', elements_arr);
    AddNullField(node, 'type_name');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'ADR' THEN
  BEGIN
    { ADR <variable-identifier>: address-of a bare variable name. Unlike the
      ADR-as-type-flavor production in ParseType (`VAR p: ADR OF T`), this
      is the value-producing expression form -- the grammar takes only a
      bare identifier, no selector chain (matches the Python reference's
      AdrExpr AST node, which likewise carries just a name). }
    pos := pos + 1;
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateNode('AdrExpr');
    AddStringField(node, 'name', name);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'SIZEOF' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    node := CreateNode('SizeofExpr');
    IF CurKind = 'IDENTIFIER' THEN
    BEGIN
      name := CurLex;
      pos := pos + 1;
      AddStringField(node, 'target', name);
    END
    ELSE
      AddField(node, 'target', ParseType);
    Expect('RPAREN');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'UPPER' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateNode('UpperExpr');
    AddStringField(node, 'name', name);
    { UPPER(p^): bound of the pointee -- for a heap super array this is the
      dynamic upper bound recorded by long-form NEW. Native codegen.pas
      rejects this deref form (no super arrays there yet), but parsing it
      is still correct regardless of what codegen later does with it. }
    AddBoolField(node, 'deref', Match('POINTER'));
    Expect('RPAREN');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'LOWER' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateNode('LowerExpr');
    AddStringField(node, 'name', name);
    AddBoolField(node, 'deref', Match('POINTER'));
    Expect('RPAREN');
    ParseFactor := node;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: Invalid factor expression'));
    res_c := puts(MakeCStr(CurKind));
    exit(1);
  END;
END;

FUNCTION ParseTerm: ADRMEM;
VAR
  left: ADRMEM;
  op_str: Str255;
  k: Str255;
BEGIN
  left := ParseFactor;
  k := CurKind;
  WHILE (k = 'MUL') OR (k = 'SLASH') OR (k = 'DIV') OR (k = 'MOD') OR (k = 'AND') DO
  BEGIN
    IF (k = 'AND') AND (NextKind = 'THEN') THEN
      k := ''
    ELSE
    BEGIN
      op_str := k;
      pos := pos + 1;
      left := MakeBinOp(op_str, left, ParseFactor);
      k := CurKind;
    END;
  END;
  ParseTerm := left;
END;

FUNCTION ParseSimpleExpression: ADRMEM;
VAR
  left: ADRMEM;
  sign_minus: BOOLEAN;
  op_str, k: Str255;
  un: ADRMEM;
BEGIN
  sign_minus := FALSE;
  IF CurKind = 'MINUS' THEN
  BEGIN
    sign_minus := TRUE;
    pos := pos + 1;
  END
  ELSE IF CurKind = 'PLUS' THEN
    pos := pos + 1;
  left := ParseTerm;
  IF sign_minus THEN
  BEGIN
    un := CreateNode('UnaryOp');
    AddStringField(un, 'op', 'MINUS');
    AddField(un, 'operand', left);
    left := un;
  END;
  k := CurKind;
  WHILE (k = 'PLUS') OR (k = 'MINUS') OR (k = 'OR') OR (k = 'XOR') DO
  BEGIN
    IF (k = 'OR') AND (NextKind = 'ELSE') THEN
      k := ''
    ELSE
    BEGIN
      op_str := k;
      pos := pos + 1;
      left := MakeBinOp(op_str, left, ParseTerm);
      k := CurKind;
    END;
  END;
  ParseSimpleExpression := left;
END;

FUNCTION ParseExpression: ADRMEM;
VAR
  left: ADRMEM;
  op_str, k: Str255;
BEGIN
  EnterExprLevel;
  left := ParseSimpleExpression;
  k := CurKind;
  IF (k = 'EQ') OR (k = 'NEQ') OR (k = 'LT') OR (k = 'LE') OR (k = 'GT') OR (k = 'GE') OR (k = 'IN') THEN
  BEGIN
    op_str := k;
    pos := pos + 1;
    ParseExpression := MakeBinOp(op_str, left, ParseSimpleExpression);
  END
  ELSE
    ParseExpression := left;
  LeaveExprLevel;
END;

FUNCTION ParseBooleanExpression: ADRMEM;
VAR
  left: ADRMEM;
  op_str: Str255;
BEGIN
  left := ParseExpression;
  WHILE ((CurKind = 'AND') AND (NextKind = 'THEN')) OR ((CurKind = 'OR') AND (NextKind = 'ELSE')) DO
  BEGIN
    IF CurKind = 'AND' THEN
      op_str := 'AND_THEN'
    ELSE
      op_str := 'OR_ELSE';
    pos := pos + 2;
    left := MakeBinOp(op_str, left, ParseExpression);
  END;
  ParseBooleanExpression := left;
END;

FUNCTION ParseWriteArg: ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateNode('WriteArg');
  AddField(node, 'expr', ParseExpression);
  IF Match('COLON') THEN
  BEGIN
    IF CurKind = 'COLON' THEN
    BEGIN
      pos := pos + 1;
      AddNullField(node, 'width');
      AddField(node, 'precision', ParseExpression);
    END
    ELSE
    BEGIN
      AddField(node, 'width', ParseExpression);
      IF Match('COLON') THEN
        AddField(node, 'precision', ParseExpression)
      ELSE
        AddNullField(node, 'precision');
    END;
  END
  ELSE
  BEGIN
    AddNullField(node, 'width');
    AddNullField(node, 'precision');
  END;
  ParseWriteArg := node;
END;

FUNCTION ParseWriteArgList: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  cJSON_AddItemToArray(arr, ParseWriteArg);
  WHILE Match('COMMA') DO
    cJSON_AddItemToArray(arr, ParseWriteArg);
  ParseWriteArgList := arr;
END;

FUNCTION ParseAssignOrCallStmt: ADRMEM;
VAR
  node, target, args_arr, saved_flags_node: ADRMEM;
  pt: PToken;
  name: Str255;
  saved_rangeck: BOOLEAN;
BEGIN
  name := CurLex;
  saved_rangeck := CurRangeCk();
  saved_flags_node := BuildMetaFlagsNode();
  pt := GetTok(1);
  { A bare (no-parens) procedure call is legal Pascal wherever a statement
    can appear, so its next token can be anything a statement can be
    followed by -- END, ELSE, UNTIL, SEMICOLON, ... -- not just SEMICOLON.
    The only tokens that mean "this identifier is an assignment target,
    not a call" are ASSIGN/EQ directly, or a selector (LBRACKET/DOT/
    POINTER) that leads into one; anything else is a proc call, mirroring
    parser.py's parse_assignment_or_proc_call (checks for ASSIGN after
    selectors, falls through to a call otherwise). }
  IF (pt^.kind = 'ASSIGN') OR (pt^.kind = 'EQ') OR (pt^.kind = 'LBRACKET') OR
     (pt^.kind = 'DOT') OR (pt^.kind = 'POINTER') THEN
  BEGIN
    node := CreateNode('AssignStmt');
    target := ParseDesignator;
    IF Match('ASSIGN') OR Match('EQ') THEN ;
    AddField(node, 'target', target);
    AddField(node, 'expr', ParseExpression);
    AddBoolField(node, 'rangeck', saved_rangeck);
    AddField(node, 'meta_flags', saved_flags_node);
    ParseAssignOrCallStmt := node;
  END
  ELSE
  BEGIN
    node := CreateNode('ProcCallStmt');
    Expect('IDENTIFIER');
    AddStringField(node, 'name', name);
    args_arr := cJSON_CreateArray;
    IF Match('LPAREN') THEN
    BEGIN
      IF CurKind <> 'RPAREN' THEN
      BEGIN
        IF StringEqual(UpperStr(name), 'WRITE') OR StringEqual(UpperStr(name), 'WRITELN') THEN
          args_arr := ParseWriteArgList
        ELSE
        BEGIN
          cJSON_AddItemToArray(args_arr, ParseExpression);
          WHILE Match('COMMA') DO
            cJSON_AddItemToArray(args_arr, ParseExpression);
        END;
      END;
      Expect('RPAREN');
    END;
    AddField(node, 'args', args_arr);
    AddBoolField(node, 'rangeck', saved_rangeck);
    AddField(node, 'meta_flags', saved_flags_node);
    ParseAssignOrCallStmt := node;
  END;
END;

FUNCTION ParseCompoundStmt: ADRMEM;
VAR
  node, stmts_arr: ADRMEM;
BEGIN
  Expect('BEGIN');
  node := CreateNode('CompoundStmt');
  stmts_arr := cJSON_CreateArray;
  WHILE (CurKind <> 'END') AND (CurKind <> 'EOF') DO
  BEGIN
    cJSON_AddItemToArray(stmts_arr, ParseStatement);
    IF CurKind = 'SEMICOLON' THEN pos := pos + 1;
  END;
  Expect('END');
  AddField(node, 'stmts', stmts_arr);
  ParseCompoundStmt := node;
END;

FUNCTION ParseCompoundStmtList: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  Expect('BEGIN');
  arr := cJSON_CreateArray;
  WHILE (CurKind <> 'END') AND (CurKind <> 'EOF') DO
  BEGIN
    cJSON_AddItemToArray(arr, ParseStatement);
    IF CurKind = 'SEMICOLON' THEN pos := pos + 1;
  END;
  Expect('END');
  ParseCompoundStmtList := arr;
END;

FUNCTION ParseIfStmt: ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  Expect('IF');
  node := CreateNode('IfStmt');
  AddField(node, 'cond', ParseBooleanExpression);
  Expect('THEN');
  AddField(node, 'then_branch', ParseStatement);
  IF Match('ELSE') THEN
    AddField(node, 'else_branch', ParseStatement)
  ELSE
    AddNullField(node, 'else_branch');
  ParseIfStmt := node;
END;

FUNCTION ParseForStmt: ADRMEM;
VAR
  node: ADRMEM;
  var_name, dir_str: Str255;
  static_flag, has_unroll: BOOLEAN;
  unroll_val: INTEGER;
  res_c: CINT;
BEGIN
  has_unroll := CurHasUnroll();
  unroll_val := CurUnrollVal();
  Expect('FOR');
  node := CreateNode('ForStmt');
  static_flag := Match('STATIC');
  var_name := CurLex;
  Expect('IDENTIFIER');
  Expect('ASSIGN');
  AddStringField(node, 'var', var_name);
  AddField(node, 'start', ParseExpression);
  IF (CurKind = 'TO') OR (CurKind = 'DOWNTO') THEN
  BEGIN
    dir_str := CurKind;
    pos := pos + 1;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: expected TO or DOWNTO'));
    exit(1);
  END;
  AddField(node, 'end', ParseExpression);
  Expect('DO');
  AddStringField(node, 'direction', dir_str);
  AddField(node, 'body', ParseStatement);
  AddBoolField(node, 'static', static_flag);
  IF has_unroll THEN
    AddIntField(node, 'unroll', unroll_val)
  ELSE
    AddNullField(node, 'unroll');
  ParseForStmt := node;
END;

FUNCTION ParseWhileStmt: ADRMEM;
VAR
  node: ADRMEM;
  has_unroll: BOOLEAN;
  unroll_val: INTEGER;
BEGIN
  has_unroll := CurHasUnroll();
  unroll_val := CurUnrollVal();
  Expect('WHILE');
  node := CreateNode('WhileStmt');
  AddField(node, 'cond', ParseBooleanExpression);
  Expect('DO');
  AddField(node, 'body', ParseStatement);
  IF has_unroll THEN
    AddIntField(node, 'unroll', unroll_val)
  ELSE
    AddNullField(node, 'unroll');
  ParseWhileStmt := node;
END;

FUNCTION ParseRepeatStmt: ADRMEM;
VAR
  node, stmts_arr: ADRMEM;
  has_unroll: BOOLEAN;
  unroll_val: INTEGER;
BEGIN
  has_unroll := CurHasUnroll();
  unroll_val := CurUnrollVal();
  Expect('REPEAT');
  node := CreateNode('RepeatStmt');
  stmts_arr := cJSON_CreateArray;
  IF CurKind <> 'UNTIL' THEN
  BEGIN
    cJSON_AddItemToArray(stmts_arr, ParseStatement);
    WHILE Match('SEMICOLON') DO
    BEGIN
      IF CurKind = 'UNTIL' THEN BREAK;
      cJSON_AddItemToArray(stmts_arr, ParseStatement);
    END;
  END;
  Expect('UNTIL');
  AddField(node, 'body', stmts_arr);
  AddField(node, 'cond', ParseBooleanExpression);
  IF has_unroll THEN
    AddIntField(node, 'unroll', unroll_val)
  ELSE
    AddNullField(node, 'unroll');
  ParseRepeatStmt := node;
END;

FUNCTION ParseCaseConstant: ADRMEM;
VAR
  e, high, node: ADRMEM;
BEGIN
  e := ParseConstant;
  IF Match('RANGE') THEN
  BEGIN
    high := ParseConstant;
    node := CreateNode('RangeExpr');
    AddField(node, 'low', e);
    AddField(node, 'high', high);
    ParseCaseConstant := node;
  END
  ELSE
    ParseCaseConstant := e;
END;

FUNCTION ParseCaseConstantList: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  cJSON_AddItemToArray(arr, ParseCaseConstant);
  WHILE Match('COMMA') DO
    cJSON_AddItemToArray(arr, ParseCaseConstant);
  ParseCaseConstantList := arr;
END;

FUNCTION ParseCaseElement: ADRMEM;
VAR
  node, constants_arr: ADRMEM;
BEGIN
  node := CreateNode('CaseElement');
  constants_arr := ParseCaseConstantList;
  Expect('COLON');
  AddField(node, 'constants', constants_arr);
  AddField(node, 'stmt', ParseStatement);
  ParseCaseElement := node;
END;

FUNCTION ParseCaseStmt: ADRMEM;
VAR
  node, elements_arr: ADRMEM;
BEGIN
  Expect('CASE');
  node := CreateNode('CaseStmt');
  AddField(node, 'expr', ParseExpression);
  Expect('OF');
  elements_arr := cJSON_CreateArray;
  IF CurKind <> 'END' THEN
  BEGIN
    cJSON_AddItemToArray(elements_arr, ParseCaseElement);
    WHILE Match('SEMICOLON') DO
    BEGIN
      IF (CurKind = 'OTHERWISE') OR (CurKind = 'END') THEN BREAK;
      cJSON_AddItemToArray(elements_arr, ParseCaseElement);
    END;
  END;
  AddField(node, 'elements', elements_arr);
  IF Match('OTHERWISE') THEN
    AddField(node, 'otherwise', ParseStatement)
  ELSE
    AddNullField(node, 'otherwise');
  Expect('END');
  AddBoolField(node, 'rangeck', CurRangeCk());
  AddField(node, 'meta_flags', BuildMetaFlagsNode());
  ParseCaseStmt := node;
END;

FUNCTION ParseWithTarget: ADRMEM;
VAR
  node, selectors_arr, sel_obj: ADRMEM;
  nm: Str255;
BEGIN
  nm := CurLex;
  Expect('IDENTIFIER');
  node := CreateNode('Designator');
  AddStringField(node, 'name', nm);
  selectors_arr := cJSON_CreateArray;
  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'INDEX');
      AddField(sel_obj, 'index_or_field', ParseExpression);
      Expect('RBRACKET');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE IF CurKind = 'DOT' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'FIELD');
      AddStringField(sel_obj, 'index_or_field', CurLex);
      Expect('IDENTIFIER');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'DEREF');
      AddNullField(sel_obj, 'index_or_field');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END;
  END;
  AddField(node, 'selectors', selectors_arr);
  ParseWithTarget := node;
END;

FUNCTION ParseWithStmt: ADRMEM;
VAR
  node, targets_arr: ADRMEM;
BEGIN
  Expect('WITH');
  node := CreateNode('WithStmt');
  targets_arr := cJSON_CreateArray;
  cJSON_AddItemToArray(targets_arr, ParseWithTarget);
  WHILE Match('COMMA') DO
    cJSON_AddItemToArray(targets_arr, ParseWithTarget);
  Expect('DO');
  AddField(node, 'targets', targets_arr);
  AddField(node, 'body', ParseStatement);
  ParseWithStmt := node;
END;

FUNCTION ParseLabelStmt: ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateNode('LabelStmt');
  IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    AddIntField(node, 'label', StrToIntVal(CurLex));
    pos := pos + 1;
  END
  ELSE
  BEGIN
    AddStringField(node, 'label', CurLex);
    pos := pos + 1;
  END;
  Expect('COLON');
  AddField(node, 'stmt', ParseStatement);
  ParseLabelStmt := node;
END;

FUNCTION ParseStatement: ADRMEM;
VAR
  node: ADRMEM;
  k: Str255;
  res_c: CINT;
BEGIN
  EnterStmtLevel;
  k := CurKind;
  { A $UNROLL(n) stamp must land on the loop keyword it hints. Catch a
    misplaced hint here rather than silently dropping it. }
  IF CurHasUnroll() AND (k <> 'FOR') AND (k <> 'WHILE') AND (k <> 'REPEAT') THEN
  BEGIN
    res_c := puts(MakeCStr('Parser Error: {$UNROLL n} must immediately precede a FOR, WHILE, or REPEAT statement'));
    exit(1);
  END;
  IF k = 'BEGIN' THEN
    ParseStatement := ParseCompoundStmt
  ELSE IF k = 'IF' THEN
    ParseStatement := ParseIfStmt
  ELSE IF k = 'FOR' THEN
    ParseStatement := ParseForStmt
  ELSE IF k = 'REPEAT' THEN
    ParseStatement := ParseRepeatStmt
  ELSE IF k = 'WHILE' THEN
    ParseStatement := ParseWhileStmt
  ELSE IF k = 'CASE' THEN
    ParseStatement := ParseCaseStmt
  ELSE IF k = 'WITH' THEN
    ParseStatement := ParseWithStmt
  ELSE IF k = 'GOTO' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('GotoStmt');
    IF CurKind = 'INTEGER_LITERAL' THEN
    BEGIN
      AddIntField(node, 'label', StrToIntVal(CurLex));
      pos := pos + 1;
    END
    ELSE
    BEGIN
      AddStringField(node, 'label', CurLex);
      pos := pos + 1;
    END;
    ParseStatement := node;
  END
  ELSE IF k = 'RETURN' THEN
  BEGIN
    pos := pos + 1;
    ParseStatement := CreateNode('ReturnStmt');
  END
  ELSE IF k = 'BREAK' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('BreakStmt');
    IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'IDENTIFIER') THEN
    BEGIN
      IF CurKind = 'INTEGER_LITERAL' THEN
        AddIntField(node, 'label', StrToIntVal(CurLex))
      ELSE
        AddStringField(node, 'label', CurLex);
      pos := pos + 1;
    END
    ELSE
      AddNullField(node, 'label');
    ParseStatement := node;
  END
  ELSE IF k = 'CYCLE' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('CycleStmt');
    IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'IDENTIFIER') THEN
    BEGIN
      IF CurKind = 'INTEGER_LITERAL' THEN
        AddIntField(node, 'label', StrToIntVal(CurLex))
      ELSE
        AddStringField(node, 'label', CurLex);
      pos := pos + 1;
    END
    ELSE
      AddNullField(node, 'label');
    ParseStatement := node;
  END
  ELSE IF ((k = 'INTEGER_LITERAL') OR (k = 'IDENTIFIER')) AND (NextKind = 'COLON') THEN
    ParseStatement := ParseLabelStmt
  ELSE IF k = 'IDENTIFIER' THEN
    ParseStatement := ParseAssignOrCallStmt
  ELSE IF (k = 'SEMICOLON') OR (k = 'END') OR (k = 'UNTIL') OR
          (k = 'ELSE') OR (k = 'OTHERWISE') OR (k = 'RPAREN') THEN
    ParseStatement := CreateNode('EmptyStmt')
  ELSE
  BEGIN
    { An empty statement is legal only at a statement boundary.  Returning
      one for arbitrary input leaves the token unconsumed and makes callers
      such as ParseCompoundStmt loop forever on malformed source. }
    res_c := puts(MakeCStr('Parser Error: expected statement'));
    exit(1);
    ParseStatement := NIL;
  END;
  LeaveStmtLevel;
END;

FUNCTION ParseIndexRange(allow_star: BOOLEAN): ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateNode('IndexRange');
  AddField(node, 'low', ParseConstant);
  Expect('RANGE');
  IF allow_star THEN
  BEGIN
    Expect('MUL');
    AddNullField(node, 'high');
  END
  ELSE
    AddField(node, 'high', ParseConstant);
  ParseIndexRange := node;
END;

FUNCTION ParseSetBase: ADRMEM;
VAR
  node, low_e, high_e: ADRMEM;
  nm: Str255;
  res_c: CINT;
BEGIN
  IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    IF NextKind = 'RANGE' THEN
    BEGIN
      low_e := ParseConstant;
      Expect('RANGE');
      high_e := ParseConstant;
      node := CreateNode('SubrangeType');
      AddField(node, 'low', low_e);
      AddField(node, 'high', high_e);
      AddNullField(node, 'host');
      ParseSetBase := node;
    END
    ELSE
    BEGIN
      nm := CurLex;
      Expect('IDENTIFIER');
      node := CreateNode('NamedType');
      AddStringField(node, 'name', nm);
      AddNullField(node, 'param');
      ParseSetBase := node;
    END;
  END
  ELSE IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'CHAR_LITERAL') OR
          (CurKind = 'STRING_LITERAL') OR (CurKind = 'BOOLEAN_LITERAL') THEN
  BEGIN
    low_e := ParseConstant;
    IF CurKind = 'RANGE' THEN
    BEGIN
      pos := pos + 1;
      high_e := ParseConstant;
      node := CreateNode('SubrangeType');
      AddField(node, 'low', low_e);
      AddField(node, 'high', high_e);
      AddNullField(node, 'host');
      ParseSetBase := node;
    END
    ELSE
    BEGIN
      node := CreateNode('BuiltinType');
      AddStringField(node, 'name', 'INTEGER');
      ParseSetBase := node;
    END;
  END
  ELSE IF (CurKind = 'INTEGER') OR (CurKind = 'REAL') OR (CurKind = 'BOOLEAN') OR
          (CurKind = 'CHAR') OR (CurKind = 'WORD') OR (CurKind = 'ADRMEM') THEN
  BEGIN
    node := CreateNode('BuiltinType');
    AddStringField(node, 'name', CurKind);
    pos := pos + 1;
    ParseSetBase := node;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: expected set base type'));
    exit(1);
  END;
END;

FUNCTION MakeTupleNode(item1, item2: ADRMEM): ADRMEM;
VAR
  node, items_arr: ADRMEM;
BEGIN
  node := cJSON_CreateObject;
  AddBoolField(node, '__tuple__', TRUE);
  items_arr := cJSON_CreateArray;
  cJSON_AddItemToArray(items_arr, item1);
  cJSON_AddItemToArray(items_arr, item2);
  AddField(node, 'items', items_arr);
  MakeTupleNode := node;
END;

FUNCTION ParseType: ADRMEM;
VAR
  node, idx_range, elem_type, base_type, space_expr: ADRMEM;
  packed_flag, is_super: BOOLEAN;
  nm: Str255;
  fields_arr, names_arr, field_type, max_len_expr, param_expr, values_arr: ADRMEM;
  variants_arr, labels_arr, arm_fields_arr, arm_node, tag_type: ADRMEM;
  tag_name: Str255;
  has_tag: BOOLEAN;
  max_len: INTEGER;
  res_c: CINT;
BEGIN
  packed_flag := Match('PACKED');
  IF (CurKind = 'ARRAY') OR (CurKind = 'SUPER') THEN
  BEGIN
    is_super := (CurKind = 'SUPER');
    IF is_super THEN
    BEGIN
      pos := pos + 1;
      Expect('ARRAY');
    END
    ELSE
      pos := pos + 1;
    Expect('LBRACKET');
    idx_range := ParseIndexRange(is_super);
    Expect('RBRACKET');
    Expect('OF');
    elem_type := ParseType;
    node := CreateNode('ArrayType');
    AddField(node, 'index_range', idx_range);
    AddField(node, 'element_type', elem_type);
    AddBoolField(node, 'packed', packed_flag);
    AddBoolField(node, 'super', is_super);
    ParseType := node;
  END
  ELSE IF CurKind = 'RECORD' THEN
  BEGIN
    pos := pos + 1;
    fields_arr := cJSON_CreateArray;
    { The fixed part ends at CASE, if there is a variant part. }
    WHILE (CurKind <> 'END') AND (CurKind <> 'CASE') DO
    BEGIN
      names_arr := ParseIdentListArr;
      Expect('COLON');
      field_type := ParseType;
      cJSON_AddItemToArray(fields_arr, MakeTupleNode(names_arr, field_type));
      IF CurKind = 'SEMICOLON' THEN
        pos := pos + 1
      ELSE
        BREAK;
    END;
    variants_arr := cJSON_CreateArray;
    tag_type := cJSON_CreateNull;
    has_tag := FALSE;
    tag_name := '';
    IF CurKind = 'CASE' THEN
    BEGIN
      pos := pos + 1;
      { A discriminant identifier is optional: CASE kind: INTEGER OF, or
        CASE INTEGER OF. }
      IF (CurKind = 'IDENTIFIER') AND (NextKind = 'COLON') THEN
      BEGIN
        has_tag := TRUE;
        tag_name := CurLex;
        pos := pos + 1;
        Expect('COLON');
      END;
      tag_type := ParseType;
      Expect('OF');
      WHILE CurKind <> 'END' DO
      BEGIN
        labels_arr := ParseCaseConstantList;
        Expect('COLON');
        Expect('LPAREN');
        arm_fields_arr := cJSON_CreateArray;
        WHILE CurKind <> 'RPAREN' DO
        BEGIN
          names_arr := ParseIdentListArr;
          Expect('COLON');
          field_type := ParseType;
          cJSON_AddItemToArray(arm_fields_arr, MakeTupleNode(names_arr, field_type));
          IF CurKind = 'SEMICOLON' THEN
            pos := pos + 1
          ELSE
            BREAK;
        END;
        Expect('RPAREN');
        arm_node := CreateNode('VariantArm');
        AddField(arm_node, 'labels', labels_arr);
        AddField(arm_node, 'fields', arm_fields_arr);
        cJSON_AddItemToArray(variants_arr, arm_node);
        IF CurKind = 'SEMICOLON' THEN
          pos := pos + 1
        ELSE
          BREAK;
      END;
    END;
    Expect('END');
    node := CreateNode('RecordType');
    AddField(node, 'fields', fields_arr);
    AddBoolField(node, 'has_tag', has_tag);
    AddStringField(node, 'tag_name', tag_name);
    AddField(node, 'tag_type', tag_type);
    AddField(node, 'variants', variants_arr);
    AddBoolField(node, 'packed', packed_flag);
    ParseType := node;
  END
  ELSE IF CurKind = 'SET' THEN
  BEGIN
    pos := pos + 1;
    Expect('OF');
    base_type := ParseSetBase;
    node := CreateNode('SetType');
    AddField(node, 'base', base_type);
    ParseType := node;
  END
  ELSE IF CurKind = 'FILE' THEN
  BEGIN
    pos := pos + 1;
    Expect('OF');
    elem_type := ParseType;
    node := CreateNode('FileType');
    AddField(node, 'element_type', elem_type);
    AddStringField(node, 'structure', 'BINARY');
    ParseType := node;
  END
  ELSE IF CurKind = 'LPAREN' THEN
  BEGIN
    pos := pos + 1;
    values_arr := ParseIdentListArr;
    Expect('RPAREN');
    node := CreateNode('EnumType');
    AddField(node, 'values', values_arr);
    ParseType := node;
  END
  ELSE IF CurKind = 'LSTRING' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    max_len_expr := ParseConstant;
    Expect('RPAREN');
    max_len := TRUNC(cJSON_GetNumberValue(cJSON_GetObjectItem(max_len_expr, MakeCStr('value'))));
    node := CreateNode('LStringType');
    AddIntField(node, 'max_len', max_len);
    ParseType := node;
  END
  ELSE IF CurKind = 'POINTER' THEN
  BEGIN
    pos := pos + 1;
    base_type := ParseType;
    node := CreateNode('PointerType');
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'POINTER');
    AddNullField(node, 'space');
    ParseType := node;
  END
  ELSE IF CurKind = 'ADR' THEN
  BEGIN
    pos := pos + 1;
    Expect('OF');
    base_type := ParseType;
    node := CreateNode('PointerType');
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'ADR');
    AddNullField(node, 'space');
    ParseType := node;
  END
  ELSE IF CurKind = 'ADS' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('PointerType');
    IF Match('LPAREN') THEN
    BEGIN
      space_expr := ParseExpression;
      Expect('RPAREN');
      AddField(node, 'space', space_expr);
    END
    ELSE
      AddNullField(node, 'space');
    Expect('OF');
    base_type := ParseType;
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'ADS');
    ParseType := node;
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    nm := CurLex;
    pos := pos + 1;
    node := CreateNode('NamedType');
    AddStringField(node, 'name', nm);
    IF Match('LPAREN') THEN
    BEGIN
      param_expr := ParseConstant;
      Expect('RPAREN');
      { NamedType.param is a bare int or identifier-name, not the full
        constant-expression node, matching parser.py's unwrapping. }
      IF StringEqual(CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('__node_type__')))), 'IntLiteral') THEN
        AddIntField(node, 'param', TRUNC(cJSON_GetNumberValue(cJSON_GetObjectItem(param_expr, MakeCStr('value')))))
      ELSE IF StringEqual(CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('__node_type__')))), 'Identifier') THEN
        AddStringField(node, 'param', CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('name')))))
      ELSE
        AddNullField(node, 'param');
    END
    ELSE
      AddNullField(node, 'param');
    ParseType := node;
  END
  ELSE IF (CurKind = 'INTEGER') OR (CurKind = 'REAL') OR (CurKind = 'BOOLEAN') OR
          (CurKind = 'CHAR') OR (CurKind = 'WORD') OR (CurKind = 'ADRMEM') THEN
  BEGIN
    node := CreateNode('BuiltinType');
    AddStringField(node, 'name', CurKind);
    pos := pos + 1;
    ParseType := node;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: expected type'));
    exit(1);
  END;
END;

FUNCTION ParseAttributeItem: ADRMEM;
VAR
  node, tuning_args: ADRMEM;
  up, c_str: Str255;
  res_c: CINT;
BEGIN
  c_str[0] := CHR(1);
  c_str[1] := 'C';
  IF (CurKind = 'READONLY') OR (CurKind = 'PUBLIC') OR (CurKind = 'STATIC') OR
     (CurKind = 'EXTERNAL') OR (CurKind = 'EXTERN') OR (CurKind = 'PURE') THEN
  BEGIN
    node := CreateNode('Attribute');
    AddStringField(node, 'name', CurKind);
    AddNullField(node, 'arg');
    pos := pos + 1;
    ParseAttributeItem := node;
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    up := UpperStr(CurLex);
    IF StringEqual(up, 'SPACE') THEN
    BEGIN
      pos := pos + 1;
      Expect('LPAREN');
      node := CreateNode('Attribute');
      AddStringField(node, 'name', 'SPACE');
      AddField(node, 'arg', ParseExpression());
      Expect('RPAREN');
      ParseAttributeItem := node;
    END
    ELSE IF ((ORD(up[0]) = 1) AND (up[1] = 'C')) OR StringEqual(up, 'CDECL') THEN
    BEGIN
      pos := pos + 1;
      node := CreateNode('Attribute');
      AddStringField(node, 'name', c_str);
      AddNullField(node, 'arg');
      ParseAttributeItem := node;
    END
    ELSE IF StringEqual(up, 'VARARGS') THEN
    BEGIN
      pos := pos + 1;
      node := CreateNode('Attribute');
      AddStringField(node, 'name', 'VARARGS');
      AddNullField(node, 'arg');
      ParseAttributeItem := node;
    END
    ELSE IF StringEqual(up, 'MAXNTID') OR StringEqual(up, 'REQNTID') OR StringEqual(up, 'MINCTASM') THEN
    BEGIN
      pos := pos + 1;
      Expect('LPAREN');
      tuning_args := cJSON_CreateArray;
      cJSON_AddItemToArray(tuning_args, ParseExpression());
      WHILE Match('COMMA') DO
        cJSON_AddItemToArray(tuning_args, ParseExpression());
      Expect('RPAREN');
      node := CreateNode('Attribute');
      AddStringField(node, 'name', up);
      AddField(node, 'arg', tuning_args);
      ParseAttributeItem := node;
    END
    ELSE
    BEGIN
      res_c := puts(MakeCStr('Parser Error: expected attribute item'));
      exit(1);
    END;
  END
  ELSE
  BEGIN
    res_c := puts(MakeCStr('Parser Error: expected attribute item'));
    exit(1);
  END;
END;

FUNCTION ParseAttributeSectionOptional: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  IF Match('LBRACKET') THEN
  BEGIN
    IF CurKind <> 'RBRACKET' THEN
    BEGIN
      cJSON_AddItemToArray(arr, ParseAttributeItem);
      WHILE Match('COMMA') DO
        cJSON_AddItemToArray(arr, ParseAttributeItem);
    END;
    Expect('RBRACKET');
  END;
  ParseAttributeSectionOptional := arr;
END;

FUNCTION ParseParamGroup: ADRMEM;
VAR
  node, names_arr, type_expr: ADRMEM;
  mode_str: Str255;
  has_mode: BOOLEAN;
BEGIN
  has_mode := FALSE;
  IF (CurKind = 'VAR') OR (CurKind = 'VARS') OR (CurKind = 'CONST') OR (CurKind = 'CONSTS') THEN
  BEGIN
    mode_str := CurKind;
    has_mode := TRUE;
    pos := pos + 1;
  END;
  names_arr := ParseIdentListArr;
  Expect('COLON');
  type_expr := ParseType;
  node := CreateNode('Param');
  IF has_mode THEN
    AddStringField(node, 'mode', mode_str)
  ELSE
    AddNullField(node, 'mode');
  AddField(node, 'names', names_arr);
  AddField(node, 'type_expr', type_expr);
  ParseParamGroup := node;
END;

FUNCTION ParseParamList: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  cJSON_AddItemToArray(arr, ParseParamGroup);
  WHILE Match('SEMICOLON') DO
  BEGIN
    IF CurKind = 'RPAREN' THEN BREAK;
    cJSON_AddItemToArray(arr, ParseParamGroup);
  END;
  ParseParamList := arr;
END;

PROCEDURE ParseConstSection(decls_arr: ADRMEM);
VAR
  node: ADRMEM;
  nm: Str255;
BEGIN
  Expect('CONST');
  WHILE CurKind = 'IDENTIFIER' DO
  BEGIN
    nm := CurLex;
    Expect('IDENTIFIER');
    Expect('EQ');
    node := CreateNode('ConstDecl');
    AddStringField(node, 'name', nm);
    AddField(node, 'value', ParseConstant);
    Expect('SEMICOLON');
    cJSON_AddItemToArray(decls_arr, node);
  END;
END;

PROCEDURE ParseTypeSection(decls_arr: ADRMEM);
VAR
  node: ADRMEM;
  nm: Str255;
BEGIN
  Expect('TYPE');
  WHILE CurKind = 'IDENTIFIER' DO
  BEGIN
    nm := CurLex;
    Expect('IDENTIFIER');
    Expect('EQ');
    node := CreateNode('TypeDecl');
    AddStringField(node, 'name', nm);
    AddField(node, 'type_expr', ParseType);
    Expect('SEMICOLON');
    cJSON_AddItemToArray(decls_arr, node);
  END;
END;

PROCEDURE ParseVarSection(decls_arr: ADRMEM);
VAR
  node, names_arr, attrs_arr: ADRMEM;
BEGIN
  Expect('VAR');
  WHILE (CurKind = 'IDENTIFIER') OR (CurKind = 'LBRACKET') DO
  BEGIN
    attrs_arr := ParseAttributeSectionOptional;
    names_arr := ParseIdentListArr;
    Expect('COLON');
    node := CreateNode('VarDecl');
    AddField(node, 'names', names_arr);
    AddField(node, 'type_expr', ParseType);
    AddField(node, 'attributes', attrs_arr);
    Expect('SEMICOLON');
    AddField(node, 'meta_flags', BuildMetaFlagsNode());
    cJSON_AddItemToArray(decls_arr, node);
  END;
END;

PROCEDURE ParseLabelSection(decls_arr: ADRMEM);
VAR
  node, labels_arr: ADRMEM;
BEGIN
  Expect('LABEL');
  node := CreateNode('LabelDecl');
  labels_arr := cJSON_CreateArray;
  IF CurKind = 'INTEGER_LITERAL' THEN
    cJSON_AddItemToArray(labels_arr, cJSON_CreateNumber(StrToIntVal(CurLex)))
  ELSE
    cJSON_AddItemToArray(labels_arr, cJSON_CreateString(MakeCStr(CurLex)));
  pos := pos + 1;
  WHILE Match('COMMA') DO
  BEGIN
    IF CurKind = 'INTEGER_LITERAL' THEN
      cJSON_AddItemToArray(labels_arr, cJSON_CreateNumber(StrToIntVal(CurLex)))
    ELSE
      cJSON_AddItemToArray(labels_arr, cJSON_CreateString(MakeCStr(CurLex)));
    pos := pos + 1;
  END;
  Expect('SEMICOLON');
  AddField(node, 'labels', labels_arr);
  cJSON_AddItemToArray(decls_arr, node);
END;

FUNCTION ParseProcDecl: ADRMEM;
VAR
  node, params_arr, attrs_arr, body_node: ADRMEM;
  nm, directive_str: Str255;
  has_directive: BOOLEAN;
BEGIN
  Expect('PROCEDURE');
  nm := CurLex;
  Expect('IDENTIFIER');
  params_arr := cJSON_CreateArray;
  IF Match('LPAREN') THEN
  BEGIN
    params_arr := ParseParamList;
    Expect('RPAREN');
  END;
  attrs_arr := ParseAttributeSectionOptional;
  Expect('SEMICOLON');
  has_directive := FALSE;
  node := CreateNode('ProcDecl');
  AddStringField(node, 'name', nm);
  AddField(node, 'params', params_arr);
  AddField(node, 'attributes', attrs_arr);
  IF (CurKind = 'EXTERN') OR (CurKind = 'EXTERNAL') OR (CurKind = 'FORWARD') THEN
  BEGIN
    directive_str := CurKind;
    has_directive := TRUE;
    pos := pos + 1;
    Expect('SEMICOLON');
    AddNullField(node, 'body');
  END
  ELSE
  BEGIN
    body_node := ParseBlock;
    Expect('SEMICOLON');
    AddField(node, 'body', body_node);
  END;
  IF has_directive THEN
    AddStringField(node, 'directive', directive_str)
  ELSE
    AddNullField(node, 'directive');
  AddBoolField(node, 'is_exported_entry', FALSE);
  ParseProcDecl := node;
END;

FUNCTION ParseFuncDecl: ADRMEM;
VAR
  node, params_arr, attrs_arr, body_node, ret_type: ADRMEM;
  nm, directive_str: Str255;
  has_directive: BOOLEAN;
BEGIN
  Expect('FUNCTION');
  nm := CurLex;
  Expect('IDENTIFIER');
  params_arr := cJSON_CreateArray;
  IF Match('LPAREN') THEN
  BEGIN
    params_arr := ParseParamList;
    Expect('RPAREN');
  END;
  Expect('COLON');
  ret_type := ParseType;
  attrs_arr := ParseAttributeSectionOptional;
  Expect('SEMICOLON');
  has_directive := FALSE;
  node := CreateNode('FuncDecl');
  AddStringField(node, 'name', nm);
  AddField(node, 'params', params_arr);
  AddField(node, 'return_type', ret_type);
  AddField(node, 'attributes', attrs_arr);
  IF (CurKind = 'EXTERN') OR (CurKind = 'EXTERNAL') OR (CurKind = 'FORWARD') THEN
  BEGIN
    directive_str := CurKind;
    has_directive := TRUE;
    pos := pos + 1;
    Expect('SEMICOLON');
    AddNullField(node, 'body');
  END
  ELSE
  BEGIN
    body_node := ParseBlock;
    Expect('SEMICOLON');
    AddField(node, 'body', body_node);
  END;
  IF has_directive THEN
    AddStringField(node, 'directive', directive_str)
  ELSE
    AddNullField(node, 'directive');
  AddBoolField(node, 'is_exported_entry', FALSE);
  ParseFuncDecl := node;
END;

PROCEDURE ParseDeclSectionsInto(decls_arr: ADRMEM);
BEGIN
  WHILE (CurKind = 'CONST') OR (CurKind = 'TYPE') OR (CurKind = 'VAR') OR
        (CurKind = 'LABEL') OR (CurKind = 'PROCEDURE') OR (CurKind = 'FUNCTION') DO
  BEGIN
    IF CurKind = 'CONST' THEN
      ParseConstSection(decls_arr)
    ELSE IF CurKind = 'TYPE' THEN
      ParseTypeSection(decls_arr)
    ELSE IF CurKind = 'VAR' THEN
      ParseVarSection(decls_arr)
    ELSE IF CurKind = 'LABEL' THEN
      ParseLabelSection(decls_arr)
    ELSE IF CurKind = 'PROCEDURE' THEN
      cJSON_AddItemToArray(decls_arr, ParseProcDecl)
    ELSE IF CurKind = 'FUNCTION' THEN
      cJSON_AddItemToArray(decls_arr, ParseFuncDecl);
  END;
END;

FUNCTION ParseInterfaceProcDecl: ADRMEM;
VAR
  node, params_arr, attrs_arr: ADRMEM;
  nm: Str255;
BEGIN
  Expect('PROCEDURE');
  nm := CurLex;
  Expect('IDENTIFIER');
  params_arr := cJSON_CreateArray;
  IF Match('LPAREN') THEN
  BEGIN
    params_arr := ParseParamList;
    Expect('RPAREN');
  END;
  attrs_arr := ParseAttributeSectionOptional;
  Expect('SEMICOLON');
  node := CreateNode('ProcDecl');
  AddStringField(node, 'name', nm);
  AddField(node, 'params', params_arr);
  AddField(node, 'attributes', attrs_arr);
  AddNullField(node, 'body');
  AddNullField(node, 'directive');
  AddBoolField(node, 'is_exported_entry', FALSE);
  ParseInterfaceProcDecl := node;
END;

FUNCTION ParseInterfaceFuncDecl: ADRMEM;
VAR
  node, params_arr, attrs_arr, ret_type: ADRMEM;
  nm: Str255;
BEGIN
  Expect('FUNCTION');
  nm := CurLex;
  Expect('IDENTIFIER');
  params_arr := cJSON_CreateArray;
  IF Match('LPAREN') THEN
  BEGIN
    params_arr := ParseParamList;
    Expect('RPAREN');
  END;
  Expect('COLON');
  ret_type := ParseType;
  attrs_arr := ParseAttributeSectionOptional;
  Expect('SEMICOLON');
  node := CreateNode('FuncDecl');
  AddStringField(node, 'name', nm);
  AddField(node, 'params', params_arr);
  AddField(node, 'return_type', ret_type);
  AddField(node, 'attributes', attrs_arr);
  AddNullField(node, 'body');
  AddNullField(node, 'directive');
  AddBoolField(node, 'is_exported_entry', FALSE);
  ParseInterfaceFuncDecl := node;
END;

PROCEDURE ParseInterfaceDeclSectionsInto(decls_arr: ADRMEM);
BEGIN
  WHILE (CurKind = 'CONST') OR (CurKind = 'TYPE') OR (CurKind = 'VAR') OR
        (CurKind = 'LABEL') OR (CurKind = 'PROCEDURE') OR (CurKind = 'FUNCTION') DO
  BEGIN
    IF CurKind = 'CONST' THEN
      ParseConstSection(decls_arr)
    ELSE IF CurKind = 'TYPE' THEN
      ParseTypeSection(decls_arr)
    ELSE IF CurKind = 'VAR' THEN
      ParseVarSection(decls_arr)
    ELSE IF CurKind = 'LABEL' THEN
      ParseLabelSection(decls_arr)
    ELSE IF CurKind = 'PROCEDURE' THEN
      cJSON_AddItemToArray(decls_arr, ParseInterfaceProcDecl)
    ELSE IF CurKind = 'FUNCTION' THEN
      cJSON_AddItemToArray(decls_arr, ParseInterfaceFuncDecl);
  END;
END;

FUNCTION ParseUsesImport: ADRMEM;
VAR
  node, imports_arr: ADRMEM;
  nm: Str255;
BEGIN
  nm := CurLex;
  Expect('IDENTIFIER');
  node := CreateNode('UseClause');
  AddStringField(node, 'name', nm);
  IF Match('LPAREN') THEN
  BEGIN
    imports_arr := ParseIdentListArr;
    Expect('RPAREN');
    AddField(node, 'imports', imports_arr);
  END
  ELSE
    AddNullField(node, 'imports');
  ParseUsesImport := node;
END;

PROCEDURE ParseUsesClauseInto(arr: ADRMEM);
BEGIN
  Expect('USES');
  cJSON_AddItemToArray(arr, ParseUsesImport);
  WHILE Match('COMMA') DO
    cJSON_AddItemToArray(arr, ParseUsesImport);
  IF CurKind = 'SEMICOLON' THEN pos := pos + 1;
END;

FUNCTION IsAtDevicePrefix(target_kind: Str255): BOOLEAN;
BEGIN
  IsAtDevicePrefix := (CurKind = 'IDENTIFIER') AND
                       StringEqual(UpperStr(CurLex), 'DEVICE') AND
                       StringEqual(NextKind, target_kind);
END;

FUNCTION ParseModuleUnit(is_device: BOOLEAN): ADRMEM;
VAR
  node, uses_arr, decls_arr: ADRMEM;
  nm: Str255;
BEGIN
  Expect('MODULE');
  nm := CurLex;
  Expect('IDENTIFIER');
  Expect('SEMICOLON');
  node := CreateNode('ModuleUnit');
  AddStringField(node, 'name', nm);
  uses_arr := cJSON_CreateArray;
  WHILE CurKind = 'USES' DO
    ParseUsesClauseInto(uses_arr);
  AddField(node, 'uses', uses_arr);
  decls_arr := cJSON_CreateArray;
  ParseDeclSectionsInto(decls_arr);
  AddField(node, 'decls', decls_arr);
  IF CurKind = 'END' THEN
  BEGIN
    Expect('END');
    Expect('DOT');
  END
  ELSE
    Expect('DOT');
  AddBoolField(node, 'is_device', is_device);
  AddField(node, 'local_interfaces', cJSON_CreateArray);
  ParseModuleUnit := node;
END;

FUNCTION ParseInterfaceUnit(is_device: BOOLEAN): ADRMEM;
VAR
  node, uses_arr, decls_arr, params_arr, discard_node: ADRMEM;
  nm: Str255;
  has_init: BOOLEAN;
BEGIN
  Expect('INTERFACE');
  Expect('SEMICOLON');
  Expect('UNIT');
  nm := CurLex;
  Expect('IDENTIFIER');
  params_arr := cJSON_CreateArray;
  IF Match('LPAREN') THEN
  BEGIN
    params_arr := ParseIdentListArr;
    Expect('RPAREN');
  END;
  Expect('SEMICOLON');
  node := CreateNode('InterfaceUnit');
  AddStringField(node, 'name', nm);
  AddField(node, 'params', params_arr);
  uses_arr := cJSON_CreateArray;
  WHILE CurKind = 'USES' DO
    ParseUsesClauseInto(uses_arr);
  AddField(node, 'uses', uses_arr);
  decls_arr := cJSON_CreateArray;
  ParseInterfaceDeclSectionsInto(decls_arr);
  AddField(node, 'decls', decls_arr);
  has_init := FALSE;
  IF CurKind = 'BEGIN' THEN
  BEGIN
    has_init := TRUE;
    discard_node := ParseCompoundStmt;
    Expect('SEMICOLON');
  END
  ELSE
  BEGIN
    Expect('END');
    Expect('SEMICOLON');
  END;
  AddBoolField(node, 'is_device', is_device);
  AddBoolField(node, 'has_init', has_init);
  ParseInterfaceUnit := node;
END;

FUNCTION ParseImplementationUnit(is_device: BOOLEAN): ADRMEM;
VAR
  node, uses_arr, decls_arr: ADRMEM;
  nm: Str255;
BEGIN
  Expect('IMPLEMENTATION');
  Expect('OF');
  nm := CurLex;
  Expect('IDENTIFIER');
  Expect('SEMICOLON');
  node := CreateNode('ImplementationUnit');
  AddStringField(node, 'name', nm);
  uses_arr := cJSON_CreateArray;
  WHILE CurKind = 'USES' DO
    ParseUsesClauseInto(uses_arr);
  AddField(node, 'uses', uses_arr);
  decls_arr := cJSON_CreateArray;
  ParseDeclSectionsInto(decls_arr);
  AddField(node, 'decls', decls_arr);
  IF CurKind = 'BEGIN' THEN
    AddField(node, 'init_body', ParseCompoundStmtList)
  ELSE
    AddNullField(node, 'init_body');
  Expect('DOT');
  AddBoolField(node, 'is_device', is_device);
  AddNullField(node, 'interface');
  AddField(node, 'local_interfaces', cJSON_CreateArray);
  ParseImplementationUnit := node;
END;

FUNCTION ParseBlock: ADRMEM;
VAR
  node, decls_arr: ADRMEM;
BEGIN
  node := CreateNode('Block');
  decls_arr := cJSON_CreateArray;
  ParseDeclSectionsInto(decls_arr);
  AddField(node, 'decls', decls_arr);

  IF CurKind = 'BEGIN' THEN
    AddField(node, 'body', ParseCompoundStmtList)
  ELSE
    AddField(node, 'body', cJSON_CreateArray);

  ParseBlock := node;
END;

FUNCTION ParseProgramUnit: ADRMEM;
VAR
  node, params_arr, uses_arr, block_node: ADRMEM;
  name: Str255;
  res_c: CINT;
BEGIN
  Expect('PROGRAM');
  name := CurLex;
  Expect('IDENTIFIER');

  node := CreateNode('ProgramUnit');
  AddStringField(node, 'name', name);

  params_arr := cJSON_CreateArray;
  IF Match('LPAREN') THEN
  BEGIN
    IF CurKind <> 'RPAREN' THEN
    BEGIN
      cJSON_AddItemToArray(params_arr, cJSON_CreateString(MakeCStr(CurLex)));
      Expect('IDENTIFIER');
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(params_arr, cJSON_CreateString(MakeCStr(CurLex)));
        Expect('IDENTIFIER');
      END;
    END;
    Expect('RPAREN');
  END;
  AddField(node, 'params', params_arr);

  Expect('SEMICOLON');

  uses_arr := cJSON_CreateArray;
  WHILE CurKind = 'USES' DO
    ParseUsesClauseInto(uses_arr);
  AddField(node, 'uses', uses_arr);

  block_node := ParseBlock;
  AddField(node, 'block', block_node);

  AddField(node, 'local_interfaces', cJSON_CreateArray);

  Expect('DOT');
  ParseProgramUnit := node;
END;

VAR
  ast_root, json_out, interfaces_arr, iface_node, local_ifaces_arr: ADRMEM;
  cand_iface, iface_name_field, unit_type_field, matched_iface: ADRMEM;
  standalone_iface: BOOLEAN;
  n_ifaces, rc: CINT;
  ii: INTEGER32;
  res_c: CINT;

BEGIN
  pos := 0;
  expr_depth := 0;
  stmt_depth := 0;
  ReadInputAndParseTokens;

  interfaces_arr := cJSON_CreateArray;
  standalone_iface := FALSE;

  WHILE (NOT standalone_iface) AND ((CurKind = 'INTERFACE') OR IsAtDevicePrefix('INTERFACE')) DO
  BEGIN
    IF CurKind = 'INTERFACE' THEN
      iface_node := ParseInterfaceUnit(FALSE)
    ELSE
    BEGIN
      pos := pos + 1;
      iface_node := ParseInterfaceUnit(TRUE);
    END;
    cJSON_AddItemToArray(interfaces_arr, iface_node);
    IF CurKind = 'EOF' THEN
    BEGIN
      standalone_iface := TRUE;
      ast_root := cJSON_GetArrayItem(interfaces_arr, 0);
    END;
  END;

  IF NOT standalone_iface THEN
  BEGIN
    IF CurKind = 'PROGRAM' THEN
      ast_root := ParseProgramUnit
    ELSE IF CurKind = 'MODULE' THEN
      ast_root := ParseModuleUnit(FALSE)
    ELSE IF IsAtDevicePrefix('MODULE') THEN
    BEGIN
      pos := pos + 1;
      ast_root := ParseModuleUnit(TRUE);
    END
    ELSE IF CurKind = 'INTERFACE' THEN
      ast_root := ParseInterfaceUnit(FALSE)
    ELSE IF IsAtDevicePrefix('INTERFACE') THEN
    BEGIN
      pos := pos + 1;
      ast_root := ParseInterfaceUnit(TRUE);
    END
    ELSE IF CurKind = 'IMPLEMENTATION' THEN
      ast_root := ParseImplementationUnit(FALSE)
    ELSE IF IsAtDevicePrefix('IMPLEMENTATION') THEN
    BEGIN
      pos := pos + 1;
      ast_root := ParseImplementationUnit(TRUE);
    END
    ELSE
    BEGIN
      res_c := puts(MakeCStr('Parser Error: expected compilation unit start'));
      exit(1);
    END;

    { Wire up any spliced leading INTERFACE header(s): attach a duplicate of
      each to local_interfaces (present on ProgramUnit/ModuleUnit/
      ImplementationUnit), and for an ImplementationUnit, transfer ownership
      of the name-matching one into its 'interface' field. }
    n_ifaces := cJSON_GetArraySize(interfaces_arr);
    IF n_ifaces > 0 THEN
    BEGIN
      unit_type_field := cJSON_GetObjectItem(ast_root, MakeCStr('__node_type__'));
      local_ifaces_arr := cJSON_GetObjectItem(ast_root, MakeCStr('local_interfaces'));
      matched_iface := NIL;
      FOR ii := 0 TO n_ifaces - 1 DO
      BEGIN
        cand_iface := cJSON_GetArrayItem(interfaces_arr, ii);
        IF local_ifaces_arr <> NIL THEN
          cJSON_AddItemToArray(local_ifaces_arr, cJSON_Duplicate(cand_iface, 1));
        IF (matched_iface = NIL) AND
           StringEqual(CStrToStr255(cJSON_GetStringValue(unit_type_field)), 'ImplementationUnit') THEN
        BEGIN
          iface_name_field := cJSON_GetObjectItem(cand_iface, MakeCStr('name'));
          IF StringEqual(UpperStr(CStrToStr255(cJSON_GetStringValue(iface_name_field))),
                          UpperStr(CStrToStr255(cJSON_GetStringValue(
                            cJSON_GetObjectItem(ast_root, MakeCStr('name')))))) THEN
            matched_iface := cand_iface;
        END;
      END;
      IF matched_iface <> NIL THEN
      BEGIN
        FOR ii := 0 TO n_ifaces - 1 DO
          IF cJSON_GetArrayItem(interfaces_arr, ii) = matched_iface THEN
          BEGIN
            matched_iface := cJSON_DetachItemFromArray(interfaces_arr, ii);
            BREAK;
          END;
        rc := cJSON_ReplaceItemInObject(ast_root, MakeCStr('interface'), matched_iface);
      END;
    END;
    cJSON_Delete(interfaces_arr);
  END;

  json_out := cJSON_Print(ast_root);
  res_c := puts(json_out);
  free(json_out);
  cJSON_Delete(ast_root);
  free(tokens_buf);
END.
