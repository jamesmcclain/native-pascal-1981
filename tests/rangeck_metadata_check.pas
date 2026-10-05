(*$INCLUDE:'jsonutil.inc'*)
PROGRAM RangeMetadataCheck(input, output);
USES jsonutil;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
PROCEDURE Walk(node: ADRMEM);
VAR i: INTEGER32; nt, nm: Str255; flags: ADRMEM;
BEGIN
  IF cJSON_IsObject(node) <> 0 THEN
  BEGIN
    nt := NodeType(node);
    IF (nt = 'ForStmt') OR (nt = 'CaseStmt') THEN
    BEGIN
      IF NOT HasKey(node, 'rangeck') THEN exit(1);
      WRITELN(nt, ' ', GetBool(node, 'rangeck'));
    END;
    IF nt = 'FuncCall' THEN
    BEGIN
      nm := GetStr(node, 'name');
      IF nm = 'Identity' THEN nm := 'IDENTITY';
      IF (nm = 'SUCC') OR (nm = 'IDENTITY') THEN
      BEGIN
        flags := GetObj(node, 'read_flags');
        IF NOT HasKey(flags, 'RANGECK') THEN exit(1);
        WRITELN(nm, ' ', GetBool(flags, 'RANGECK'));
      END;
    END;
  END;
  IF (cJSON_IsObject(node) <> 0) OR (cJSON_IsArray(node) <> 0) THEN
    FOR i := 0 TO ArrSize(node) - 1 DO Walk(pas_cjson_child(node, i));
END;
BEGIN Walk(ReadAllStdin) END.
