{ Declaration and compilation-unit parsing implementation. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
(*$INCLUDE:'ps_expr.inc'*)
(*$INCLUDE:'ps_stmt.inc'*)
(*$INCLUDE:'ps_decl.inc'*)
IMPLEMENTATION OF ps_decl;
USES ps_base, ps_expr, ps_stmt;

FUNCTION ParseBlock: ADRMEM; FORWARD;
FUNCTION ParseProcDecl: ADRMEM; FORWARD;
FUNCTION ParseFuncDecl: ADRMEM; FORWARD;

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
      EPrint('Parser Error: expected attribute item');
      exit(1);
    END;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: expected attribute item');
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

PROCEDURE ParseInterfaceDirectiveInto(node: ADRMEM);
{ An interface routine header is body-less by construction, so a directive is
  never required here -- but EXTERN/EXTERNAL may still be written to say that
  the body lives in a C library or another object rather than in this unit's
  own IMPLEMENTATION (the routine_directive production in
  docs/ebnf_grammar.md). The typechecker's HasExternMarkerDecl reads it, as
  does codegen's IsCForeignDecl for the SysV C ABI.

  FORWARD is deliberately not accepted: it promises a definition later in the
  same declaration part, which an INTERFACE does not have. }
VAR
  directive_str: Str255;
  has_directive: BOOLEAN;
BEGIN
  has_directive := FALSE;
  IF (CurKind = 'EXTERN') OR (CurKind = 'EXTERNAL') THEN
  BEGIN
    directive_str := CurKind;
    has_directive := TRUE;
    pos := pos + 1;
    Expect('SEMICOLON');
  END;
  IF has_directive THEN
    AddStringField(node, 'directive', directive_str)
  ELSE
    AddNullField(node, 'directive');
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
  ParseInterfaceDirectiveInto(node);
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
  ParseInterfaceDirectiveInto(node);
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
BEGIN
END.
