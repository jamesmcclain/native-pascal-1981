{ Native token/AST probe; missing flags must not pass as false defaults. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM InitMetadataCheck(input, output);
USES jsonutil;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsBool(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
PROCEDURE Report(name: Str255; flags: ADRMEM);
BEGIN
  IF (NOT HasKey(flags, 'INITCK')) OR
     (cJSON_IsBool(GetObj(flags, 'INITCK')) = 0) THEN
  BEGIN
    EPrint('missing or non-boolean INITCK snapshot');
    exit(1);
  END;
  WRITELN(name, ':', GetBool(flags, 'INITCK'));
END;
PROCEDURE Walk(node: ADRMEM);
VAR
  i: INTEGER32;
  name: Str255;
BEGIN
  IF cJSON_IsObject(node) <> 0 THEN
  BEGIN
    IF GetStr(node, 'kind') = 'IDENTIFIER' THEN
    BEGIN
      name := GetStr(node, 'lexeme');
      IF (ORD(name[0]) >= 3) AND (name[1] = 'c') AND
         (name[2] = 'k') AND (name[3] = '_') THEN
        Report(name, GetObj(node, 'flags'));
    END
    ELSE IF NodeType(node) = 'VarDecl' THEN
    BEGIN
      name := CStrToStr255(cJSON_GetStringValue(ArrItem(GetObj(node, 'names'), 0)));
      Report(name, GetObj(node, 'meta_flags'));
    END;
  END;
  IF (cJSON_IsObject(node) <> 0) OR (cJSON_IsArray(node) <> 0) THEN
    FOR i := 0 TO ArrSize(node) - 1 DO Walk(pas_cjson_child(node, i));
END;
BEGIN
  Walk(ReadAllStdin);
END.
