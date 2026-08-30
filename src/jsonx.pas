{ IMPLEMENTATION of jsonx. See jsonx.inc for the contract and for the
  ownership rules, which are the part of this unit that bites.

  Keys and short values are staged through a local ARRAY OF CHAR rather than
  through a malloc'd copy the way jsonutil's MakeCStr does. cJSON duplicates
  every key and every string value as it stores it, so the staging buffer only
  has to survive the call it is passed to -- and a local one does, without
  leaking 256 bytes per JSON field the way the older idiom does. }

(*$INCLUDE:'bytebuf.inc'*)
(*$INCLUDE:'jsonx.inc'*)

IMPLEMENTATION OF jsonx;

TYPE
  JxCBuf  = ARRAY [0..255] OF CHAR;
  JxPCBuf = ^JxCBuf;

FUNCTION cJSON_Parse(val: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE cJSON_Delete(item: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_PrintUnformatted(item: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE cJSON_free(ptr: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateArray: ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateString(val: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateNumber(num: REAL): ADRMEM [C]; EXTERN;
PROCEDURE cJSON_AddItemToObject(obj: ADRMEM; key: ADRMEM; item: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_AddItemToArray(arr: ADRMEM; item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetObjectItem(obj: ADRMEM; key: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_Compare(left: ADRMEM; right: ADRMEM; case_sensitive: CINT): CINT [C]; EXTERN;
FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetNumberValue(item: ADRMEM): REAL [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsString(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsBool(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsTrue(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION strlen(s: ADRMEM): CSIZE_T [C]; EXTERN;
FUNCTION pas_cjson_int32(item: ADRMEM): CINT [C]; EXTERN;

{ Stage an LSTRING as a NUL-terminated C string in caller-owned storage.
  Anything past 255 characters cannot be in an LSTRING to begin with, so no
  truncation happens here that the caller has not already suffered. }
PROCEDURE JxStage(s: ByteStr; VAR out: JxCBuf);
VAR
  i, len: INTEGER;
BEGIN
  len := ORD(s[0]);
  FOR i := 1 TO len DO
    out[i - 1] := s[i];
  out[len] := CHR(0);
END;

{ ------------------------------------------------------------------ }
{ Parsing and printing                                                }
{ ------------------------------------------------------------------ }

FUNCTION JxParse(text: ADRMEM): ADRMEM;
BEGIN
  IF text = NIL THEN
    JxParse := NIL
  ELSE
    JxParse := cJSON_Parse(text);
END;

FUNCTION JxParseBuf(VAR b: ByteBuf): ADRMEM;
BEGIN
  JxParseBuf := cJSON_Parse(BufCStr(b));
END;

PROCEDURE JxDelete(node: ADRMEM);
BEGIN
  IF node <> NIL THEN cJSON_Delete(node);
END;

FUNCTION JxPrintToBuf(node: ADRMEM; VAR out: ByteBuf): BOOLEAN;
VAR
  text: ADRMEM;
BEGIN
  IF node = NIL THEN
    JxPrintToBuf := FALSE
  ELSE
  BEGIN
    text := cJSON_PrintUnformatted(node);
    IF text = NIL THEN
      JxPrintToBuf := FALSE
    ELSE
    BEGIN
      BufAppendCStr(out, text);
      { cJSON's own deallocator, not free: the library may have been built
        with hooks installed, and mixing allocators is the kind of bug that
        only shows up on someone else's machine. }
      cJSON_free(text);
      JxPrintToBuf := TRUE;
    END;
  END;
END;

{ ------------------------------------------------------------------ }
{ Inspection                                                          }
{ ------------------------------------------------------------------ }

FUNCTION JxIsObject(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsObject := (node <> NIL) AND (cJSON_IsObject(node) <> 0);
END;

FUNCTION JxIsArray(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsArray := (node <> NIL) AND (cJSON_IsArray(node) <> 0);
END;

FUNCTION JxIsString(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsString := (node <> NIL) AND (cJSON_IsString(node) <> 0);
END;

FUNCTION JxIsNumber(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsNumber := (node <> NIL) AND (cJSON_IsNumber(node) <> 0);
END;

FUNCTION JxIsBool(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsBool := (node <> NIL) AND (cJSON_IsBool(node) <> 0);
END;

FUNCTION JxIsNull(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsNull := (node <> NIL) AND (cJSON_IsNull(node) <> 0);
END;

FUNCTION JxIsTrue(node: ADRMEM): BOOLEAN;
BEGIN
  JxIsTrue := (node <> NIL) AND (cJSON_IsTrue(node) <> 0);
END;

FUNCTION JxGet(obj: ADRMEM; key: ByteStr): ADRMEM;
VAR
  kbuf: JxCBuf;
BEGIN
  IF obj = NIL THEN
    JxGet := NIL
  ELSE
  BEGIN
    JxStage(key, kbuf);
    JxGet := cJSON_GetObjectItem(obj, ADR kbuf);
  END;
END;

FUNCTION JxHas(obj: ADRMEM; key: ByteStr): BOOLEAN;
BEGIN
  JxHas := JxGet(obj, key) <> NIL;
END;

FUNCTION JxEqual(left: ADRMEM; right: ADRMEM): BOOLEAN;
BEGIN
  JxEqual := cJSON_Compare(left, right, 1) <> 0;
END;

FUNCTION JxArrSize(arr: ADRMEM): INTEGER32;
BEGIN
  IF arr = NIL THEN
    JxArrSize := 0
  ELSE
    JxArrSize := RETYPE(INTEGER32, cJSON_GetArraySize(arr));
END;

FUNCTION JxArrItem(arr: ADRMEM; i: INTEGER32): ADRMEM;
BEGIN
  IF arr = NIL THEN
    JxArrItem := NIL
  ELSE
    JxArrItem := cJSON_GetArrayItem(arr, RETYPE(CINT, i));
END;

FUNCTION JxStrRaw(node: ADRMEM): ADRMEM;
BEGIN
  IF node = NIL THEN
    JxStrRaw := NIL
  ELSE
    JxStrRaw := cJSON_GetStringValue(node);
END;

FUNCTION JxStrLen(node: ADRMEM): INTEGER32;
VAR
  p: ADRMEM;
BEGIN
  p := JxStrRaw(node);
  IF p = NIL THEN
    JxStrLen := 0
  ELSE
    JxStrLen := RETYPE(INTEGER32, strlen(p));
END;

FUNCTION JxNumValue(node: ADRMEM): REAL;
BEGIN
  IF NOT JxIsNumber(node) THEN
    JxNumValue := 0.0
  ELSE
    JxNumValue := cJSON_GetNumberValue(node);
END;

FUNCTION JxIntValue(node: ADRMEM): INTEGER32;
BEGIN
  JxIntValue := RETYPE(INTEGER32, pas_cjson_int32(node));
END;

FUNCTION JxStrToBuf(node: ADRMEM; VAR out: ByteBuf): BOOLEAN;
VAR
  p: ADRMEM;
BEGIN
  p := JxStrRaw(node);
  IF p = NIL THEN
    JxStrToBuf := FALSE
  ELSE
  BEGIN
    BufAppendCStr(out, p);
    JxStrToBuf := TRUE;
  END;
END;

FUNCTION JxGetStrToBuf(obj: ADRMEM; key: ByteStr; VAR out: ByteBuf): BOOLEAN;
BEGIN
  JxGetStrToBuf := JxStrToBuf(JxGet(obj, key), out);
END;

FUNCTION JxGetNum(obj: ADRMEM; key: ByteStr): REAL;
VAR
  item: ADRMEM;
BEGIN
  item := JxGet(obj, key);
  IF item = NIL THEN
    JxGetNum := 0.0
  ELSE
    JxGetNum := cJSON_GetNumberValue(item);
END;

FUNCTION JxGetInt(obj: ADRMEM; key: ByteStr): INTEGER32;
BEGIN
  JxGetInt := JxIntValue(JxGet(obj, key));
END;

PROCEDURE JxGetStr(obj: ADRMEM; key: ByteStr; VAR out: ByteStr);
VAR
  p: ADRMEM;
  pbuf: JxPCBuf;
  i, len: INTEGER;
BEGIN
  out := '';
  p := JxStrRaw(JxGet(obj, key));
  IF p <> NIL THEN
  BEGIN
    pbuf := p;
    len := 0;
    WHILE (len < 255) AND (pbuf^[len] <> CHR(0)) DO
      len := len + 1;
    out[0] := CHR(len);
    FOR i := 1 TO len DO
      out[i] := pbuf^[i - 1];
  END;
END;

{ ------------------------------------------------------------------ }
{ Building                                                            }
{ ------------------------------------------------------------------ }

FUNCTION JxNewObject: ADRMEM;
BEGIN
  JxNewObject := cJSON_CreateObject;
END;

FUNCTION JxNewArray: ADRMEM;
BEGIN
  JxNewArray := cJSON_CreateArray;
END;

FUNCTION JxNewStr(s: ByteStr): ADRMEM;
VAR
  vbuf: JxCBuf;
BEGIN
  JxStage(s, vbuf);
  JxNewStr := cJSON_CreateString(ADR vbuf);
END;

FUNCTION JxNewStrFromBuf(VAR b: ByteBuf): ADRMEM;
BEGIN
  { BufCStr terminates in place; cJSON copies immediately, so the pointer
    need not outlive this call. }
  JxNewStrFromBuf := cJSON_CreateString(BufCStr(b));
END;

FUNCTION JxNewNum(v: REAL): ADRMEM;
BEGIN
  JxNewNum := cJSON_CreateNumber(v);
END;

PROCEDURE JxArrAppend(arr: ADRMEM; item: ADRMEM);
VAR
  ignored: CINT;
BEGIN
  IF (arr <> NIL) AND (item <> NIL) THEN
    ignored := cJSON_AddItemToArray(arr, item);
END;

PROCEDURE JxAddItem(obj: ADRMEM; key: ByteStr; item: ADRMEM);
VAR
  kbuf: JxCBuf;
BEGIN
  IF (obj <> NIL) AND (item <> NIL) THEN
  BEGIN
    JxStage(key, kbuf);
    cJSON_AddItemToObject(obj, ADR kbuf, item);
  END;
END;

PROCEDURE JxAddStr(obj: ADRMEM; key: ByteStr; val: ByteStr);
BEGIN
  JxAddItem(obj, key, JxNewStr(val));
END;

PROCEDURE JxAddStrFromBuf(obj: ADRMEM; key: ByteStr; VAR val: ByteBuf);
BEGIN
  JxAddItem(obj, key, JxNewStrFromBuf(val));
END;

PROCEDURE JxAddNum(obj: ADRMEM; key: ByteStr; val: REAL);
BEGIN
  JxAddItem(obj, key, JxNewNum(val));
END;

PROCEDURE JxAddInt(obj: ADRMEM; key: ByteStr; val: INTEGER32);
BEGIN
  JxAddItem(obj, key, JxNewNum(val));
END;

BEGIN
END.
