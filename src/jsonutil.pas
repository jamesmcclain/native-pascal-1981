{ Shared Str255/cJSON-node helpers for the native pascal1981 stages (lexer.pas,
  parser.pas, and later typechecker.pas). Factored out once two independent
  copies of this boilerplate existed, to avoid a third. Compiles to its own
  object file; callers splice jsonutil.inc and USES jsonutil, then link
  against this unit's object file. }

(*$INCLUDE:'jsonutil.inc'*)
IMPLEMENTATION OF jsonutil;

FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateString(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNumber(num: REAL): ADRMEM [C]; EXTERN;
FUNCTION pas_int64_to_double(v: INTEGER64): REAL [C]; EXTERN;
FUNCTION cJSON_CreateBool(b: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNull: ADRMEM [C]; EXTERN;
PROCEDURE cJSON_AddItemToObject(obj: ADRMEM; key: ADRMEM; item: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_Parse(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetObjectItem(obj: ADRMEM; key: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C]; EXTERN;
FUNCTION pas_cjson_int32(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsTrue(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION getchar: CINT [C]; EXTERN;
PROCEDURE free(ptr: ADRMEM) [C]; EXTERN;
PROCEDURE pas_eprint(msg: ADRMEM) [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;

FUNCTION MakeCStr(s: Str255): ADRMEM;
VAR
  raw: ADRMEM;
  pbuf: PCharBuf;
  i, len: INTEGER;
BEGIN
  len := ORD(s[0]);
  raw := malloc(256);
  pbuf := raw;
  FOR i := 0 TO 255 DO pbuf^[i] := CHR(0);
  FOR i := 1 TO len DO pbuf^[i - 1] := s[i];
  pbuf^[len] := CHR(0);
  MakeCStr := raw;
END;

FUNCTION CStrToStr255(ptr: ADRMEM): Str255;
VAR
  res: Str255;
  pbuf: PCharBuf;
  len, i: INTEGER;
BEGIN
  res := '';
  IF ptr <> NIL THEN
  BEGIN
    pbuf := ptr;
    len := 0;
    WHILE (len < 255) AND (pbuf^[len] <> CHR(0)) DO
      len := len + 1;
    res[0] := CHR(len);
    FOR i := 1 TO len DO
      res[i] := pbuf^[i - 1];
  END;
  CStrToStr255 := res;
END;

PROCEDURE AddField(obj: ADRMEM; key_str: Str255; val_node: ADRMEM);
VAR
  key_ptr: ADRMEM;
BEGIN
  key_ptr := MakeCStr(key_str);
  cJSON_AddItemToObject(obj, key_ptr, val_node);
END;

PROCEDURE AddStringField(obj: ADRMEM; key_str: Str255; val_str: Str255);
VAR
  v_ptr: ADRMEM;
BEGIN
  v_ptr := MakeCStr(val_str);
  AddField(obj, key_str, cJSON_CreateString(v_ptr));
END;

PROCEDURE AddIntField(obj: ADRMEM; key_str: Str255; val_int: INTEGER64);
BEGIN
  { INTEGER64, not INTEGER. This took the dialect's 16-bit INTEGER, and
    quietly truncated every value written through it -- which is where an
    integer literal above 32767 was lost on its way into the AST: the lexer
    read 40000 correctly and the parser stored -25536, so codegen never saw
    anything else. A narrower parameter here would have to be RETYPEd at
    every call site, which is exactly what the parser used to do. The JSON
    number it becomes is a double, so values are exact up to 2^53. }
  AddField(obj, key_str, cJSON_CreateNumber(pas_int64_to_double(val_int)));
END;

PROCEDURE AddRealField(obj: ADRMEM; key_str: Str255; val_real: REAL);
BEGIN
  AddField(obj, key_str, cJSON_CreateNumber(val_real));
END;

PROCEDURE AddBoolField(obj: ADRMEM; key_str: Str255; val_bool: BOOLEAN);
BEGIN
  IF val_bool THEN
    AddField(obj, key_str, cJSON_CreateBool(1))
  ELSE
    AddField(obj, key_str, cJSON_CreateBool(0));
END;

PROCEDURE AddNullField(obj: ADRMEM; key_str: Str255);
BEGIN
  AddField(obj, key_str, cJSON_CreateNull);
END;

FUNCTION CreateNode(type_name: Str255): ADRMEM;
VAR
  obj: ADRMEM;
BEGIN
  obj := cJSON_CreateObject;
  AddStringField(obj, '__node_type__', type_name);
  CreateNode := obj;
END;

FUNCTION ParseJson(text: ADRMEM): ADRMEM;
BEGIN
  ParseJson := cJSON_Parse(text);
END;

PROCEDURE EPrintC(msg: ADRMEM);
BEGIN
  pas_eprint(msg);
END;

PROCEDURE EPrint(msg: Str255);
BEGIN
  EPrintC(MakeCStr(msg));
END;

FUNCTION NodeType(obj: ADRMEM): Str255;
BEGIN
  IF obj = NIL THEN
    NodeType := ''
  ELSE
    NodeType := CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(obj, MakeCStr('__node_type__'))));
END;

FUNCTION GetObj(obj: ADRMEM; key: Str255): ADRMEM;
BEGIN
  IF obj = NIL THEN
    GetObj := NIL
  ELSE
    GetObj := cJSON_GetObjectItem(obj, MakeCStr(key));
END;

FUNCTION GetStr(obj: ADRMEM; key: Str255): Str255;
VAR
  item: ADRMEM;
BEGIN
  item := GetObj(obj, key);
  IF item = NIL THEN
    GetStr := ''
  ELSE
    GetStr := CStrToStr255(cJSON_GetStringValue(item));
END;

FUNCTION GetInt(obj: ADRMEM; key: Str255): INTEGER32;
VAR
  item: ADRMEM;
BEGIN
  { Not TRUNC. TRUNC produces this dialect's INTEGER, which is 16 bits, so
    every value from 32768 up wrapped on the way out of a function whose
    declared result is INTEGER32 -- silently, and far from the call site.
    pas_cjson_int32 does the conversion in the runtime, in 32 bits.

    No stage reads a value that large today, so this fixes no live bug in the
    compiler; it makes the declared result type true, which is what the next
    caller will assume. Note that array bounds do NOT come through here
    intact: ResolveIntLiteral in cg_types.pas returns INTEGER, and that is
    where a bound above 32767 is lost. See docs/dialect_notes.md. }
  item := GetObj(obj, key);
  IF item = NIL THEN
    GetInt := 0
  ELSE
    GetInt := RETYPE(INTEGER32, pas_cjson_int32(item));
END;

FUNCTION GetReal(obj: ADRMEM; key: Str255): REAL;
VAR
  item: ADRMEM;
BEGIN
  item := GetObj(obj, key);
  IF item = NIL THEN
    GetReal := 0.0
  ELSE
    GetReal := cJSON_GetNumberValue(item);
END;

FUNCTION GetBool(obj: ADRMEM; key: Str255): BOOLEAN;
VAR
  item: ADRMEM;
BEGIN
  item := GetObj(obj, key);
  IF item = NIL THEN
    GetBool := FALSE
  ELSE
    GetBool := cJSON_IsTrue(item) <> 0;
END;

FUNCTION ArrSize(arr: ADRMEM): INTEGER32;
BEGIN
  IF arr = NIL THEN
    ArrSize := 0
  ELSE
    ArrSize := cJSON_GetArraySize(arr);
END;

FUNCTION ArrItem(arr: ADRMEM; i: INTEGER32): ADRMEM;
BEGIN
  ArrItem := cJSON_GetArrayItem(arr, i);
END;

FUNCTION HasKey(obj: ADRMEM; key: Str255): BOOLEAN;
BEGIN
  HasKey := GetObj(obj, key) <> NIL;
END;

FUNCTION ReadAllStdin: ADRMEM;
VAR
  raw_input, old_buf: ADRMEM;
  cap, len, i: INTEGER32;
  input_ch: CINT;
  p_in, p_out, p_in_base, p_out_base: ^CHAR;
  json_root: ADRMEM;
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
    { getchar's CINT result is always -1 or a byte value 0..255 here (the
      WHILE guard above excludes -1), but CHR wants a plain INTEGER and the
      language has no implicit CINT/INTEGER32 -> INTEGER narrowing; RETYPE
      makes the deliberate truncation explicit. }
    p_in^ := CHR(RETYPE(INTEGER, input_ch));
    len := len + 1;
    input_ch := getchar;
  END;
  p_in_base := raw_input;
  p_in := p_in_base + len;
  p_in^ := CHR(0);

  json_root := cJSON_Parse(raw_input);
  free(raw_input);
  IF json_root = NIL THEN
  BEGIN
    EPrint('Error: Failed to parse input AST JSON');
    exit(1);
  END;
  ReadAllStdin := json_root;
END;

BEGIN
END.
