{ Statement parsing implementation. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
(*$INCLUDE:'ps_expr.inc'*)
(*$INCLUDE:'ps_stmt.inc'*)
IMPLEMENTATION OF ps_stmt;
USES ps_base, ps_expr;

FUNCTION ParseStatement: ADRMEM; FORWARD;
FUNCTION ParseCompoundStmt: ADRMEM; FORWARD;
FUNCTION ParseCompoundStmtList: ADRMEM; FORWARD;
FUNCTION ParseIfStmt: ADRMEM; FORWARD;
FUNCTION ParseForStmt: ADRMEM; FORWARD;
FUNCTION ParseWhileStmt: ADRMEM; FORWARD;
FUNCTION ParseRepeatStmt: ADRMEM; FORWARD;
FUNCTION ParseCaseStmt: ADRMEM; FORWARD;
FUNCTION ParseWithStmt: ADRMEM; FORWARD;

FUNCTION ParseWriteArg: ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateTriviaNode('WriteArg');
  AddField(node, 'expr', ParseExpression);
  IF Match('COLON') THEN
  BEGIN
    IF CurKind = 'COLON' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
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
    node := CreateTriviaNode('AssignStmt');
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
    node := CreateTriviaNode('ProcCallStmt');
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
  node, stmts_arr, stmt_node: ADRMEM;
  start_pos: INTEGER32;
BEGIN
  Expect('BEGIN');
  node := CreateTriviaNode('CompoundStmt');
  stmts_arr := cJSON_CreateArray;
  WHILE (CurKind <> 'END') AND (CurKind <> 'EOF') DO
  BEGIN
    start_pos := pos;
    stmt_node := ParseStatement;
    PinTrailingCommentTarget(stmt_node);
    cJSON_AddItemToArray(stmts_arr, stmt_node);
    IF CurKind = 'SEMICOLON' THEN BEGIN RelayTokenTrivia; pos := pos + 1; END;
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
  arr, stmt_node: ADRMEM;
  start_pos: INTEGER32;
BEGIN
  Expect('BEGIN');
  arr := cJSON_CreateArray;
  WHILE (CurKind <> 'END') AND (CurKind <> 'EOF') DO
  BEGIN
    start_pos := pos;
    stmt_node := ParseStatement;
    PinTrailingCommentTarget(stmt_node);
    cJSON_AddItemToArray(arr, stmt_node);
    IF CurKind = 'SEMICOLON' THEN BEGIN RelayTokenTrivia; pos := pos + 1; END;
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
  node := CreateTriviaNode('IfStmt');
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
  node := CreateTriviaNode('ForStmt');
  static_flag := Match('STATIC');
  var_name := CurLex;
  Expect('IDENTIFIER');
  Expect('ASSIGN');
  AddStringField(node, 'var', var_name);
  AddField(node, 'start', ParseExpression);
  IF (CurKind = 'TO') OR (CurKind = 'DOWNTO') THEN
  BEGIN
    dir_str := CurKind;
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
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
  node := CreateTriviaNode('WhileStmt');
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
  node := CreateTriviaNode('RepeatStmt');
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
  node := CreateTriviaNode('CaseElement');
  constants_arr := ParseCaseConstantList;
  Expect('COLON');
  AddField(node, 'constants', constants_arr);
  AddField(node, 'stmt', ParseStatement);
  ParseCaseElement := node;
END;

FUNCTION ParseCaseStmt: ADRMEM;
VAR
  node, elements_arr, elem_node: ADRMEM;
BEGIN
  Expect('CASE');
  node := CreateTriviaNode('CaseStmt');
  AddField(node, 'expr', ParseExpression);
  Expect('OF');
  elements_arr := cJSON_CreateArray;
  IF CurKind <> 'END' THEN
  BEGIN
    elem_node := ParseCaseElement;
    PinTrailingCommentTarget(elem_node);
    cJSON_AddItemToArray(elements_arr, elem_node);
    WHILE Match('SEMICOLON') DO
    BEGIN
      IF (CurKind = 'OTHERWISE') OR (CurKind = 'END') THEN BREAK;
      elem_node := ParseCaseElement;
      PinTrailingCommentTarget(elem_node);
      cJSON_AddItemToArray(elements_arr, elem_node);
    END;
  END;
  AddField(node, 'elements', elements_arr);
  IF Match('OTHERWISE') THEN
  BEGIN
    elem_node := ParseStatement;
    PinTrailingCommentTarget(elem_node);
    AddField(node, 'otherwise', elem_node);
  END
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
  node := CreateTriviaNode('Designator');
  AddStringField(node, 'name', nm);
  selectors_arr := cJSON_CreateArray;
  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      sel_obj := CreateTriviaNode('Selector');
      AddStringField(sel_obj, 'kind', 'INDEX');
      AddField(sel_obj, 'index_or_field', ParseExpression);
      Expect('RBRACKET');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE IF CurKind = 'DOT' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      sel_obj := CreateTriviaNode('Selector');
      AddStringField(sel_obj, 'kind', 'FIELD');
      AddStringField(sel_obj, 'index_or_field', CurLex);
      Expect('IDENTIFIER');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END
    ELSE
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      sel_obj := CreateTriviaNode('Selector');
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
  node := CreateTriviaNode('WithStmt');
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
  node := CreateTriviaNode('LabelStmt');
  IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    AddIntField(node, 'label', StrToIntVal(CurLex));
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
  END
  ELSE
  BEGIN
    AddStringField(node, 'label', CurLex);
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
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
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('GotoStmt');
    IF CurKind = 'INTEGER_LITERAL' THEN
    BEGIN
      AddIntField(node, 'label', StrToIntVal(CurLex));
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
    END
    ELSE
    BEGIN
      AddStringField(node, 'label', CurLex);
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
    END;
    ParseStatement := node;
  END
  ELSE IF k = 'RETURN' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    ParseStatement := CreateTriviaNode('ReturnStmt');
  END
  ELSE IF k = 'BREAK' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('BreakStmt');
    IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'IDENTIFIER') THEN
    BEGIN
      IF CurKind = 'INTEGER_LITERAL' THEN
        AddIntField(node, 'label', StrToIntVal(CurLex))
      ELSE
        AddStringField(node, 'label', CurLex);
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
    END
    ELSE
      AddNullField(node, 'label');
    ParseStatement := node;
  END
  ELSE IF k = 'CYCLE' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('CycleStmt');
    IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'IDENTIFIER') THEN
    BEGIN
      IF CurKind = 'INTEGER_LITERAL' THEN
        AddIntField(node, 'label', StrToIntVal(CurLex))
      ELSE
        AddStringField(node, 'label', CurLex);
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
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
    ParseStatement := CreateTriviaNode('EmptyStmt')
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

BEGIN
END.
