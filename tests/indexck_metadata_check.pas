{ Native-only AST probe: metadata is semantic, not reference-parser trivia. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM IndexMetadataCheck(input, output);
USES jsonutil;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
PROCEDURE Walk(node: ADRMEM);
VAR i: INTEGER32;
BEGIN
  IF cJSON_IsObject(node) <> 0 THEN
    IF GetStr(node, 'kind') = 'INDEX' THEN
    BEGIN
      IF NOT HasKey(node, 'indexck') THEN
      BEGIN
        EPrint('missing per-index INDEXCK snapshot');
        exit(1);
      END;
      WRITELN(GetBool(node, 'indexck'));
    END;
  IF (cJSON_IsObject(node) <> 0) OR (cJSON_IsArray(node) <> 0) THEN
    FOR i := 0 TO ArrSize(node) - 1 DO Walk(pas_cjson_child(node, i));
END;
BEGIN
  Walk(ReadAllStdin);
END.
