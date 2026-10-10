(*$INCLUDE:'jsonutil.inc'*)
PROGRAM ByteMetadataCheck(input, output);
USES jsonutil;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
PROCEDURE cJSON_DeleteItemFromObject(item: ADRMEM; key: ADRMEM) [C]; EXTERN;
FUNCTION cJSON_PrintUnformatted(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION puts(s: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
VAR calls: INTEGER; root: ADRMEM; discard: CINT;
PROCEDURE Walk(node: ADRMEM);
VAR i: INTEGER32; location: ADRMEM; expected: BOOLEAN;
BEGIN
  IF cJSON_IsObject(node) <> 0 THEN
    IF NodeType(node) = 'FuncCall' THEN
      IF GetStr(node, 'name') = 'BYWORD' THEN
      BEGIN
        calls := calls + 1;
        expected := (calls = 2) OR (calls = 3);
        IF NOT HasKey(node, 'rangeck') THEN exit(1);
        IF GetBool(node, 'rangeck') <> expected THEN exit(2);
        location := GetObj(node, 'op_location');
        IF (GetInt(location, 'line') <= 0) OR (GetInt(location, 'column') <= 0) THEN exit(3);
        { Exercise legacy fallback without changing expression read_flags. }
        cJSON_DeleteItemFromObject(node, MakeCStr('rangeck'));
        cJSON_DeleteItemFromObject(node, MakeCStr('op_location'));
      END;
  IF (cJSON_IsObject(node) <> 0) OR (cJSON_IsArray(node) <> 0) THEN
    FOR i := 0 TO ArrSize(node) - 1 DO Walk(pas_cjson_child(node, i));
END;
BEGIN
  calls := 0;
  root := ReadAllStdin;
  Walk(root);
  IF calls <> 4 THEN exit(4);
  discard := puts(cJSON_PrintUnformatted(root));
END.
