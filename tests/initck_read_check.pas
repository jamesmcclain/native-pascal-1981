{ Native read-site AST probe: inspect the same nodes codegen receives. }
(*$INCLUDE:'jsonutil.inc'*)
PROGRAM InitReadCheck(input, output);
USES jsonutil;
FUNCTION pas_cjson_child(item: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsObject(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsArray(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsBool(item: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(status: CINT) [C]; EXTERN;
PROCEDURE Walk(node: ADRMEM);
VAR
  i: INTEGER32;
  nt, name: Str255;
  flags: ADRMEM;
  report: BOOLEAN;
BEGIN
  IF cJSON_IsObject(node) <> 0 THEN
  BEGIN
    nt := NodeType(node);
    name := GetStr(node, 'name');
    report := ((nt = 'Identifier') OR (nt = 'Designator')) AND
              (ORD(name[0]) >= 3) AND (name[1] = 'r') AND
              (name[2] = 's') AND (name[3] = '_');
    IF (nt = 'UpperExpr') OR (nt = 'FuncCall') THEN report := TRUE;
    IF (nt = 'Selector') AND
       ((GetStr(node, 'kind') = 'INDEX') OR (GetStr(node, 'kind') = 'DEREF')) THEN
    BEGIN
      name := GetStr(node, 'kind');
      report := TRUE;
    END;
    IF report THEN
    BEGIN
      flags := GetObj(node, 'read_flags');
      IF (NOT HasKey(flags, 'INITCK')) OR
         (cJSON_IsBool(GetObj(flags, 'INITCK')) = 0) THEN
      BEGIN
        EPrint('missing or non-boolean read-site INITCK snapshot');
        exit(1);
      END;
      WRITELN(nt, ':', name, ':', GetBool(flags, 'INITCK'));
    END;
  END;
  IF (cJSON_IsObject(node) <> 0) OR (cJSON_IsArray(node) <> 0) THEN
    FOR i := 0 TO ArrSize(node) - 1 DO Walk(pas_cjson_child(node, i));
END;
BEGIN
  Walk(ReadAllStdin);
END.
