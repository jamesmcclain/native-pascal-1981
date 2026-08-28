{ Pascal-1981 Native Parser implementation in extended IBM Pascal 2.0 dialect. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
(*$INCLUDE:'ps_expr.inc'*)
PROGRAM pascal1981_parse(input, output);

USES jsonutil, ps_base, ps_expr;

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
  start_pos: INTEGER32;
BEGIN
  Expect('BEGIN');
  node := CreateNode('CompoundStmt');
  stmts_arr := cJSON_CreateArray;
  WHILE (CurKind <> 'END') AND (CurKind <> 'EOF') DO
  BEGIN
    start_pos := pos;
    cJSON_AddItemToArray(stmts_arr, ParseStatement);
    IF CurKind = 'SEMICOLON' THEN pos := pos + 1;
    IF pos = start_pos THEN
    BEGIN
      EPrint('Parser Error: statement failed to advance token stream');
      exit(1);
    END;
  END;
  Expect('END');
  AddField(node, 'stmts', stmts_arr);
  ParseCompoundStmt := node;
END;

FUNCTION ParseCompoundStmtList: ADRMEM;
VAR
  arr: ADRMEM;
  start_pos: INTEGER32;
BEGIN
  Expect('BEGIN');
  arr := cJSON_CreateArray;
  WHILE (CurKind <> 'END') AND (CurKind <> 'EOF') DO
  BEGIN
    start_pos := pos;
    cJSON_AddItemToArray(arr, ParseStatement);
    IF CurKind = 'SEMICOLON' THEN pos := pos + 1;
    IF pos = start_pos THEN
    BEGIN
      EPrint('Parser Error: statement failed to advance token stream');
      exit(1);
    END;
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
    EPrint('Parser Error: expected TO or DOWNTO');
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
    EPrint('Parser Error: {$UNROLL n} must immediately precede a FOR, WHILE, or REPEAT statement');
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
          (k = 'ELSE') OR (k = 'OTHERWISE') THEN
    ParseStatement := CreateNode('EmptyStmt')
  ELSE
  BEGIN
    { An empty statement is legal only at a statement boundary.  Returning
      one for arbitrary input leaves the token unconsumed and makes callers
      such as ParseCompoundStmt loop forever on malformed source. }
    EPrint('Parser Error: expected statement');
    exit(1);
    ParseStatement := NIL;
  END;
  LeaveStmtLevel;
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
      EPrint('Parser Error: expected compilation unit start');
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
