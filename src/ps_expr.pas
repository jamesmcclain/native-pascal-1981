{ Expression and type parsing implementation. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
(*$INCLUDE:'ps_expr.inc'*)
IMPLEMENTATION OF ps_expr;
USES ps_base;

VAR bound_expr_depth: INTEGER;
  sequential_depth: INTEGER; { the expr_depth whose ParseExpression may be
    followed by AND THEN/OR ELSE: an IF, WHILE or UNTIL condition's
    operand (ParseBooleanExpression); 0 outside a condition }

FUNCTION ParseExpression: ADRMEM; FORWARD;
FUNCTION ParseBooleanExpression: ADRMEM; FORWARD;
FUNCTION ParseSimpleExpression: ADRMEM; FORWARD;
FUNCTION ParseTerm: ADRMEM; FORWARD;
FUNCTION ParseFactor: ADRMEM; FORWARD;
FUNCTION ParseFactorBody(flags: ADRMEM): ADRMEM; FORWARD;
FUNCTION ParseType: ADRMEM; FORWARD;
FUNCTION ParseConstant: ADRMEM; FORWARD;
FUNCTION ParseCaseConstant: ADRMEM; FORWARD;
FUNCTION ParseCaseConstantList: ADRMEM; FORWARD;
PROCEDURE AddOpLocation(node: ADRMEM; tok: PToken); FORWARD;

FUNCTION ParseIdentifier: ADRMEM;
VAR
  node: ADRMEM;
  name: Str255;
BEGIN
  node := CreateTriviaNode('Identifier');
  name := CurLex;
  Expect('IDENTIFIER');
  AddStringField(node, 'name', name);
  ParseIdentifier := node;
END;

FUNCTION ParseIndexSelector: ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateTriviaNode('Selector');
  AddStringField(node, 'kind', 'INDEX');
  { Snapshot before parsing: nested indexes and later directives must not
    overwrite the setting at this index expression's first token. }
  AddBoolField(node, 'indexck', CurIndexCk());
  AddOpLocation(node, GetTok(0));
  AddField(node, 'read_flags', BuildMetaFlagsNode());
  AddField(node, 'index_or_field', ParseExpression);
  ParseIndexSelector := node;
END;

FUNCTION DerefLocation: ADRMEM;
{ The `^` token's coordinates: a DEREF reads its pointer there (INITCK). }
VAR
  location: ADRMEM;
  tok: PToken;
BEGIN
  tok := GetTok(0);
  location := cJSON_CreateObject;
  AddIntField(location, 'line', tok^.line);
  AddIntField(location, 'column', tok^.col);
  DerefLocation := location;
END;

FUNCTION ParseDerefSelector: ADRMEM;
VAR
  node, flags, location: ADRMEM;
BEGIN
  flags := BuildMetaFlagsNode();
  location := DerefLocation;
  Expect('POINTER');
  node := CreateTriviaNode('Selector');
  AddStringField(node, 'kind', 'DEREF');
  AddField(node, 'read_flags', flags);
  AddField(node, 'read_location', location);
  AddNullField(node, 'index_or_field');
  ParseDerefSelector := node;
END;

FUNCTION ParseDesignatorRest(name: Str255): ADRMEM;
VAR
  node, selectors_arr, sel_obj: ADRMEM;
  has_sel: BOOLEAN;
BEGIN
  selectors_arr := cJSON_CreateArray;
  has_sel := FALSE;

  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    has_sel := TRUE;
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      sel_obj := ParseIndexSelector;
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(selectors_arr, sel_obj);
        sel_obj := ParseIndexSelector;
      END;
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
    ELSE IF CurKind = 'POINTER' THEN
    BEGIN
      sel_obj := ParseDerefSelector;
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END;
  END;

  IF has_sel THEN
  BEGIN
    node := CreateTriviaNode('Designator');
    AddStringField(node, 'name', name);
    AddField(node, 'selectors', selectors_arr);
    ParseDesignatorRest := node;
  END
  ELSE
  BEGIN
    node := CreateTriviaNode('Identifier');
    AddStringField(node, 'name', name);
    ParseDesignatorRest := node;
  END;
END;

FUNCTION ParseDesignator: ADRMEM;
VAR
  node, selectors_arr, sel_obj: ADRMEM;
  name: Str255;
BEGIN
  node := CreateTriviaNode('Designator');
  AddField(node, 'read_flags', BuildMetaFlagsNode());
  AddField(node, 'location', CurLocation);
  name := CurLex;
  Expect('IDENTIFIER');
  AddStringField(node, 'name', name);
  selectors_arr := cJSON_CreateArray;

  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      sel_obj := ParseIndexSelector;
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(selectors_arr, sel_obj);
        sel_obj := ParseIndexSelector;
      END;
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
    ELSE IF CurKind = 'POINTER' THEN
    BEGIN
      sel_obj := ParseDerefSelector;
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END;
  END;

  AddField(node, 'selectors', selectors_arr);
  ParseDesignator := node;
END;

FUNCTION NextKind: Str255;
VAR
  pt: PToken;
  res: Str255;
BEGIN
  pt := GetTok(1);
  res := pt^.kind;
  NextKind := res;
END;

FUNCTION IsMathckOp(op_str: Str255): BOOLEAN;
{ Binary operators whose source token carries a MATHCK snapshot. Whether a
  given use is integer arithmetic is the typechecker's/codegen's decision. }
BEGIN
  IsMathckOp := (op_str = 'PLUS') OR (op_str = 'MINUS') OR (op_str = 'MUL') OR
    (op_str = 'DIV') OR (op_str = 'MOD');
END;

FUNCTION IsMathckBuiltin(name: Str255): BOOLEAN;
{ Builtin calls whose function-name token carries a MATHCK snapshot. A user
  routine that shadows one of these names is the typechecker's concern. }
VAR
  up: Str255;
BEGIN
  up := UpperStr(name);
  IsMathckBuiltin := StringEqual(up, 'SUCC') OR StringEqual(up, 'PRED') OR
    StringEqual(up, 'ABS') OR StringEqual(up, 'SQR') OR
    StringEqual(up, 'VSUM') OR StringEqual(up, 'VPROD');
END;

FUNCTION IsConversionBuiltin(name: Str255): BOOLEAN;
{ Builtin calls whose always-on range check reports the function name's
  coordinates (no directive snapshot: IBM checks them unconditionally). }
VAR
  up: Str255;
BEGIN
  up := UpperStr(name);
  IsConversionBuiltin := StringEqual(up, 'TRUNC') OR StringEqual(up, 'ROUND');
END;

PROCEDURE AddOpLocation(node: ADRMEM; tok: PToken);
VAR
  location: ADRMEM;
BEGIN
  location := cJSON_CreateObject;
  AddIntField(location, 'line', tok^.line);
  AddIntField(location, 'column', tok^.col);
  AddField(node, 'op_location', location);
END;

PROCEDURE AddChrSnapshot(node: ADRMEM; tok: PToken);
BEGIN
  AddBoolField(node, 'rangeck', tok^.f_rangeck);
  AddOpLocation(node, tok);
END;

PROCEDURE AddMathckSnapshot(node: ADRMEM; tok: PToken);
{ The operator or function-name token's effective MATHCK and coordinates.
  Callers capture tok before advancing past it, so directives inside the
  operands or arguments cannot change the operation's setting. }
BEGIN
  AddBoolField(node, 'mathck', tok^.f_mathck);
  AddOpLocation(node, tok);
END;

FUNCTION MakeBinOp(op_str: Str255; left, right: ADRMEM): ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateTriviaNode('BinOp');
  AddStringField(node, 'op', op_str);
  AddField(node, 'left', left);
  AddField(node, 'right', right);
  MakeBinOp := node;
END;

FUNCTION ParseActualParameterList: ADRMEM;
VAR
  args_arr: ADRMEM;
BEGIN
  args_arr := cJSON_CreateArray;
  IF CurKind <> 'RPAREN' THEN
  BEGIN
    cJSON_AddItemToArray(args_arr, ParseExpression);
    WHILE Match('COMMA') DO
      cJSON_AddItemToArray(args_arr, ParseExpression);
  END;
  ParseActualParameterList := args_arr;
END;

FUNCTION ParseIdentListArr: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  cJSON_AddItemToArray(arr, cJSON_CreateString(MakeCStr(CurLex)));
  Expect('IDENTIFIER');
  WHILE Match('COMMA') DO
  BEGIN
    cJSON_AddItemToArray(arr, cJSON_CreateString(MakeCStr(CurLex)));
    Expect('IDENTIFIER');
  END;
  ParseIdentListArr := arr;
END;

FUNCTION ParseConstant: ADRMEM;
VAR
  node, args_arr_const: ADRMEM;
  val_str: Str255;
  sign_neg: BOOLEAN;
  res_c: CINT;
  name_tok: PToken;
BEGIN
  { Mirrors parser.py's parse_constant precedence exactly: an unsigned
    literal/identifier is tried first (no sign consumed here), and a leading
    +/- sign is only legal directly before INTEGER_LITERAL/REAL_LITERAL --
    e.g. -'A' must be rejected, not silently accepted. }
  IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('IntLiteral');
    AddIntField(node, 'value', CurValueInt());
    Expect('INTEGER_LITERAL');
    ParseConstant := node;
  END
  ELSE IF CurKind = 'REAL_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('RealLiteral');
    val_str := CurLex;
    Expect('REAL_LITERAL');
    AddRealField(node, 'value', StrToRealVal(val_str));
    ParseConstant := node;
  END
  ELSE IF CurKind = 'CHAR_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('CharLiteral');
    val_str := CurValueStr;
    Expect('CHAR_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseConstant := node;
  END
  ELSE IF CurKind = 'STRING_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('StringLiteral');
    val_str := CurLex;
    Expect('STRING_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseConstant := node;
  END
  ELSE IF CurKind = 'BOOLEAN_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('BoolLiteral');
    val_str := CurLex;
    Expect('BOOLEAN_LITERAL');
    AddBoolField(node, 'value', StringEqual(UpperStr(val_str), 'TRUE'));
    ParseConstant := node;
  END
  ELSE IF CurKind = 'NIL' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    ParseConstant := CreateTriviaNode('NilLiteral');
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    val_str := CurLex;
    name_tok := GetTok(0);
    Expect('IDENTIFIER');
    IF (StringEqual(UpperStr(val_str), 'WRD') OR StringEqual(UpperStr(val_str), 'BYWORD') OR
        StringEqual(UpperStr(val_str), 'ORD') OR StringEqual(UpperStr(val_str), 'CHR') OR
        StringEqual(UpperStr(val_str), 'SUCC') OR StringEqual(UpperStr(val_str), 'PRED')) AND
       (CurKind = 'LPAREN') THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      node := CreateTriviaNode('FuncCall');
      AddStringField(node, 'name', val_str);
      IF IsMathckBuiltin(val_str) THEN AddMathckSnapshot(node, name_tok)
      ELSE IF StringEqual(UpperStr(val_str), 'CHR') THEN AddChrSnapshot(node, name_tok)
      ELSE IF IsConversionBuiltin(val_str) THEN AddOpLocation(node, name_tok);
      args_arr_const := cJSON_CreateArray;
      cJSON_AddItemToArray(args_arr_const, ParseConstant());
      WHILE CurKind = 'COMMA' DO
      BEGIN
        BEGIN RelayTokenTrivia; pos := pos + 1; END;
        cJSON_AddItemToArray(args_arr_const, ParseConstant());
      END;
      Expect('RPAREN');
      AddField(node, 'args', args_arr_const);
      ParseConstant := node;
    END
    ELSE
    BEGIN
      node := CreateTriviaNode('Identifier');
      AddStringField(node, 'name', val_str);
      ParseConstant := node;
    END;
  END
  ELSE IF (CurKind = 'PLUS') OR (CurKind = 'MINUS') THEN
  BEGIN
    sign_neg := (CurKind = 'MINUS');
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    IF CurKind = 'INTEGER_LITERAL' THEN
    BEGIN
      node := CreateTriviaNode('IntLiteral');
      IF sign_neg THEN
        AddIntField(node, 'value', -CurValueInt())
      ELSE
        AddIntField(node, 'value', CurValueInt());
      Expect('INTEGER_LITERAL');
      ParseConstant := node;
    END
    ELSE IF CurKind = 'REAL_LITERAL' THEN
    BEGIN
      node := CreateTriviaNode('RealLiteral');
      val_str := CurLex;
      Expect('REAL_LITERAL');
      IF sign_neg THEN
        AddRealField(node, 'value', -StrToRealVal(val_str))
      ELSE
        AddRealField(node, 'value', StrToRealVal(val_str));
      ParseConstant := node;
    END
    ELSE
    BEGIN
      EPrint('Parser Error: expected numeric constant');
      exit(1);
    END;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: expected constant');
    exit(1);
  END;
END;

FUNCTION ParseSetElement: ADRMEM;
VAR
  e, high, node: ADRMEM;
BEGIN
  e := ParseExpression;
  IF Match('RANGE') THEN
  BEGIN
    high := ParseExpression;
    node := CreateTriviaNode('RangeExpr');
    AddField(node, 'low', e);
    AddField(node, 'high', high);
    ParseSetElement := node;
  END
  ELSE
    ParseSetElement := e;
END;

{ Capture before consuming any token. In particular, calls and designators
  are built after their arguments/selectors, when the lexer state may differ.
  Parentheses are transparent: retain the enclosed consumer's own snapshot. }
FUNCTION ParseFactor: ADRMEM;
VAR
  node, flags, location: ADRMEM;
  tok: PToken;
  parenthesized: BOOLEAN;
BEGIN
  parenthesized := CurKind = 'LPAREN';
  tok := GetTok(0);
  location := cJSON_CreateObject;
  AddIntField(location, 'line', tok^.line);
  AddIntField(location, 'column', tok^.col);
  flags := BuildMetaFlagsNode();
  node := ParseFactorBody(flags);
  IF NOT parenthesized THEN
  BEGIN
    IF NOT HasKey(node, 'read_flags') THEN
      AddField(node, 'read_flags', flags);
    AddField(node, 'read_location', location);
  END
  ELSE cJSON_Delete(location);
  ParseFactor := node;
END;

FUNCTION ParseFactorBody(flags: ADRMEM): ADRMEM;
VAR
  node, expr, args_arr, elements_arr: ADRMEM;
  val_str, name, kop: Str255;
  res_c: CINT;
  name_tok: PToken;
BEGIN
  IF CurKind = 'NOT' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('UnaryOp');
    AddStringField(node, 'op', 'NOT');
    AddField(node, 'operand', ParseFactor);
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('IntLiteral');
    AddIntField(node, 'value', CurValueInt());
    Expect('INTEGER_LITERAL');
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'REAL_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('RealLiteral');
    val_str := CurLex;
    Expect('REAL_LITERAL');
    AddRealField(node, 'value', StrToRealVal(val_str));
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'CHAR_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('CharLiteral');
    val_str := CurValueStr;
    Expect('CHAR_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'STRING_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('StringLiteral');
    val_str := CurLex;
    Expect('STRING_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'BOOLEAN_LITERAL' THEN
  BEGIN
    node := CreateTriviaNode('BoolLiteral');
    val_str := CurLex;
    Expect('BOOLEAN_LITERAL');
    AddBoolField(node, 'value', StringEqual(val_str, 'TRUE') OR StringEqual(val_str, 'true'));
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'NIL' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('NilLiteral');
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    name := CurLex;
    IF (name = 'RETYPE') AND (NextKind = 'LPAREN') THEN
    BEGIN
      pos := pos + 2;
      val_str := CurLex;
      Expect('IDENTIFIER');
      Expect('COMMA');
      expr := ParseExpression;
      Expect('RPAREN');
      node := CreateTriviaNode('RetypeExpr');
      AddStringField(node, 'type_id', val_str);
      AddField(node, 'expr', expr);
      AddField(node, 'selectors', cJSON_CreateArray);
      ParseFactorBody := node;
    END
    ELSE IF NextKind = 'LPAREN' THEN
    BEGIN
      name_tok := GetTok(0);
      pos := pos + 2;
      IF CurKind <> 'RPAREN' THEN
        args_arr := ParseActualParameterList
      ELSE
        args_arr := cJSON_CreateArray;
      Expect('RPAREN');
      node := CreateTriviaNode('FuncCall');
      AddStringField(node, 'name', name);
      IF IsMathckBuiltin(name) THEN AddMathckSnapshot(node, name_tok)
      ELSE IF StringEqual(UpperStr(name), 'CHR') THEN AddChrSnapshot(node, name_tok)
      ELSE IF IsConversionBuiltin(name) THEN AddOpLocation(node, name_tok);
      AddField(node, 'args', args_arr);
      IF (bound_expr_depth > 0) AND
         ((CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER')) THEN
      BEGIN
        { The call and postfix consumer must own separate JSON snapshots. }
        AddField(node, 'read_flags', cJSON_Duplicate(flags, 1));
        expr := ParseDesignatorRest('');
        args_arr := CreateTriviaNode('PostfixExpr');
        AddField(args_arr, 'base', node);
        AddField(args_arr, 'selectors', GetObj(expr, 'selectors'));
        node := args_arr;
      END;
      ParseFactorBody := node;
    END
    ELSE
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      ParseFactorBody := ParseDesignatorRest(name);
    END;
  END
  ELSE IF CurKind = 'LPAREN' THEN
  BEGIN
    Expect('LPAREN');
    expr := ParseExpression;
    Expect('RPAREN');
    ParseFactorBody := expr;
  END
  ELSE IF CurKind = 'LBRACKET' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    elements_arr := cJSON_CreateArray;
    IF CurKind <> 'RBRACKET' THEN
    BEGIN
      cJSON_AddItemToArray(elements_arr, ParseSetElement);
      WHILE Match('COMMA') DO
        cJSON_AddItemToArray(elements_arr, ParseSetElement);
    END;
    Expect('RBRACKET');
    node := CreateTriviaNode('SetConstructor');
    AddField(node, 'elements', elements_arr);
    AddNullField(node, 'type_name');
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'ADR' THEN
  BEGIN
    { ADR <variable-identifier>: address-of a bare variable name. Unlike the
      ADR-as-type-flavor production in ParseType (`VAR p: ADR OF T`), this
      is the value-producing expression form -- the grammar takes only a
      bare identifier, no selector chain (matches the Python reference's
      AdrExpr AST node, which likewise carries just a name). }
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateTriviaNode('AdrExpr');
    AddStringField(node, 'name', name);
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'SIZEOF' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('LPAREN');
    node := CreateTriviaNode('SizeofExpr');
    IF CurKind = 'IDENTIFIER' THEN
    BEGIN
      name := CurLex;
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      AddStringField(node, 'target', name);
    END
    ELSE
      AddField(node, 'target', ParseType);
    Expect('RPAREN');
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'UPPER' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('LPAREN');
    node := CreateTriviaNode('UpperExpr');
    bound_expr_depth := bound_expr_depth + 1;
    AddField(node, 'operand', ParseExpression);
    bound_expr_depth := bound_expr_depth - 1;
    Expect('RPAREN');
    ParseFactorBody := node;
  END
  ELSE IF CurKind = 'LOWER' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('LPAREN');
    node := CreateTriviaNode('LowerExpr');
    bound_expr_depth := bound_expr_depth + 1;
    AddField(node, 'operand', ParseExpression);
    bound_expr_depth := bound_expr_depth - 1;
    Expect('RPAREN');
    ParseFactorBody := node;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: Invalid factor expression');
    EPrint(CurKind);
    exit(1);
  END;
END;

FUNCTION ParseTerm: ADRMEM;
VAR
  left: ADRMEM;
  op_str: Str255;
  k: Str255;
  op_tok: PToken;
BEGIN
  left := ParseFactor;
  k := CurKind;
  WHILE (k = 'MUL') OR (k = 'SLASH') OR (k = 'DIV') OR (k = 'MOD') OR (k = 'AND') DO
  BEGIN
    IF (k = 'AND') AND (NextKind = 'THEN') THEN
      k := ''
    ELSE
    BEGIN
      op_str := k;
      { Snapshot at the operator token, before the right operand's tokens. }
      op_tok := GetTok(0);
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      left := MakeBinOp(op_str, left, ParseFactor);
      IF IsMathckOp(op_str) THEN AddMathckSnapshot(left, op_tok);
      k := CurKind;
    END;
  END;
  ParseTerm := left;
END;

FUNCTION ParseSimpleExpression: ADRMEM;
VAR
  left: ADRMEM;
  sign_minus: BOOLEAN;
  op_tok, sign_tok: PToken;
  op_str, k: Str255;
  un: ADRMEM;
BEGIN
  sign_minus := FALSE;
  IF CurKind = 'MINUS' THEN
  BEGIN
    sign_minus := TRUE;
    { The UnaryOp is built after its operand: snapshot the sign token now. }
    sign_tok := GetTok(0);
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
  END
  ELSE IF CurKind = 'PLUS' THEN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
  left := ParseTerm;
  IF sign_minus THEN
  BEGIN
    un := CreateTriviaNode('UnaryOp');
    AddStringField(un, 'op', 'MINUS');
    AddField(un, 'operand', left);
    AddMathckSnapshot(un, sign_tok);
    left := un;
  END;
  k := CurKind;
  WHILE (k = 'PLUS') OR (k = 'MINUS') OR (k = 'OR') OR (k = 'XOR') DO
  BEGIN
    IF (k = 'OR') AND (NextKind = 'ELSE') THEN
      k := ''
    ELSE
    BEGIN
      op_str := k;
      op_tok := GetTok(0);
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      left := MakeBinOp(op_str, left, ParseTerm);
      IF IsMathckOp(op_str) THEN AddMathckSnapshot(left, op_tok);
      k := CurKind;
    END;
  END;
  ParseSimpleExpression := left;
END;

FUNCTION ParseExpression: ADRMEM;
VAR
  left: ADRMEM;
  op_str, k: Str255;
BEGIN
  EnterExprLevel;
  left := ParseSimpleExpression;
  k := CurKind;
  IF (k = 'EQ') OR (k = 'NEQ') OR (k = 'LT') OR (k = 'LE') OR (k = 'GT') OR (k = 'GE') OR (k = 'IN') THEN
  BEGIN
    op_str := k;
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    ParseExpression := MakeBinOp(op_str, left, ParseSimpleExpression);
  END
  ELSE
    ParseExpression := left;
  { The 1981 manual: AND THEN/OR ELSE "can only be used in the Boolean
    expression of an IF, WHILE, or UNTIL clause, but not in other
    expressions. They cannot occur in parentheses". Say so, rather than
    report the RPAREN or statement end that is missing. }
  IF (expr_depth <> sequential_depth) AND
     (((CurKind = 'AND') AND (NextKind = 'THEN')) OR ((CurKind = 'OR') AND (NextKind = 'ELSE'))) THEN
  BEGIN
    EPrint('Parser Error: AND THEN/OR ELSE can only join the operands of an IF, WHILE or UNTIL condition, not in parentheses or another expression');
    exit(1);
  END;
  LeaveExprLevel;
END;

FUNCTION ParseBooleanExpression: ADRMEM;
VAR
  left: ADRMEM;
  op_str: Str255;
  saved_depth: INTEGER;
BEGIN
  saved_depth := sequential_depth;
  sequential_depth := expr_depth + 1;
  left := ParseExpression;
  WHILE ((CurKind = 'AND') AND (NextKind = 'THEN')) OR ((CurKind = 'OR') AND (NextKind = 'ELSE')) DO
  BEGIN
    IF CurKind = 'AND' THEN
      op_str := 'AND_THEN'
    ELSE
      op_str := 'OR_ELSE';
    pos := pos + 2;
    left := MakeBinOp(op_str, left, ParseExpression);
  END;
  sequential_depth := saved_depth;
  ParseBooleanExpression := left;
END;

FUNCTION ParseCaseConstant: ADRMEM;
VAR
  e, high, node: ADRMEM;
BEGIN
  e := ParseConstant;
  IF Match('RANGE') THEN
  BEGIN
    high := ParseConstant;
    node := CreateTriviaNode('RangeExpr');
    AddField(node, 'low', e);
    AddField(node, 'high', high);
    ParseCaseConstant := node;
  END
  ELSE
    ParseCaseConstant := e;
END;

FUNCTION ParseCaseConstantList: ADRMEM;
VAR
  arr: ADRMEM;
BEGIN
  arr := cJSON_CreateArray;
  cJSON_AddItemToArray(arr, ParseCaseConstant);
  WHILE Match('COMMA') DO
    cJSON_AddItemToArray(arr, ParseCaseConstant);
  ParseCaseConstantList := arr;
END;

FUNCTION ParseIndexRange(allow_star: BOOLEAN): ADRMEM;
VAR
  node: ADRMEM;
  nm: Str255;
BEGIN
  { A fixed array can use an ordinal type identifier instead of an explicit
    subrange. Do not resolve the name here: CONSTs and variables have the
    same token, and the typechecker must reject them in type position. The
    builtins (BOOLEAN, CHAR, INTEGER, WORD, ...) are predeclared identifiers,
    not keywords, so they lex as IDENTIFIER and take the same NamedType
    path; later stages fall back to the predeclared names. SUPER ARRAY
    bounds still require lo..*; a named type is not a lower bound. }
  IF NOT allow_star THEN
  BEGIN
    IF (CurKind = 'IDENTIFIER') AND (NextKind = 'RBRACKET') THEN
    BEGIN
      nm := CurLex;
      node := CreateTriviaNode('NamedType');
      AddStringField(node, 'name', nm);
      AddNullField(node, 'param');
      Expect('IDENTIFIER');
      ParseIndexRange := node;
      RETURN;
    END;
  END;
  node := CreateTriviaNode('IndexRange');
  AddField(node, 'low', ParseConstant);
  Expect('RANGE');
  IF allow_star THEN
  BEGIN
    Expect('MUL');
    AddNullField(node, 'high');
  END
  ELSE
    AddField(node, 'high', ParseConstant);
  ParseIndexRange := node;
END;

FUNCTION ParseSetBase: ADRMEM;
VAR
  node, low_e, high_e: ADRMEM;
  nm: Str255;
  res_c: CINT;
BEGIN
  IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    IF NextKind = 'RANGE' THEN
    BEGIN
      low_e := ParseConstant;
      Expect('RANGE');
      high_e := ParseConstant;
      node := CreateTriviaNode('SubrangeType');
      AddField(node, 'low', low_e);
      AddField(node, 'high', high_e);
      AddNullField(node, 'host');
      ParseSetBase := node;
    END
    ELSE
    BEGIN
      nm := CurLex;
      Expect('IDENTIFIER');
      node := CreateTriviaNode('NamedType');
      AddStringField(node, 'name', nm);
      AddNullField(node, 'param');
      ParseSetBase := node;
    END;
  END
  ELSE IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'CHAR_LITERAL') OR
          (CurKind = 'STRING_LITERAL') OR (CurKind = 'BOOLEAN_LITERAL') OR
          (CurKind = 'MINUS') OR (CurKind = 'PLUS') THEN
  BEGIN
    low_e := ParseConstant;
    IF CurKind = 'RANGE' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      high_e := ParseConstant;
      node := CreateTriviaNode('SubrangeType');
      AddField(node, 'low', low_e);
      AddField(node, 'high', high_e);
      AddNullField(node, 'host');
      ParseSetBase := node;
    END
    ELSE
    BEGIN
      node := CreateTriviaNode('BuiltinType');
      AddStringField(node, 'name', 'INTEGER');
      ParseSetBase := node;
    END;
  END
  ELSE IF (CurKind = 'INTEGER') OR (CurKind = 'REAL') OR (CurKind = 'BOOLEAN') OR
          (CurKind = 'CHAR') OR (CurKind = 'WORD') OR (CurKind = 'ADRMEM') THEN
  BEGIN
    node := CreateTriviaNode('BuiltinType');
    AddStringField(node, 'name', CurKind);
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    ParseSetBase := node;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: expected set base type');
    exit(1);
  END;
END;

FUNCTION MakeTupleNode(item1, item2: ADRMEM): ADRMEM;
{ Built with a bare cJSON_CreateObject, not CreateTriviaNode -- a tuple
  built here (a RECORD field, a VariantArm field) has no leading_comments
  or trailing_comment slot, and its callers in ParseType's RECORD branch
  consume the field-separator SEMICOLON with a raw pos := pos + 1 that
  never calls RelayTokenTrivia. A comment on a record field is therefore
  silently dropped by the parser today, not merely misattached -- see the
  matching note on PrintRecordFields in pretty81.pas. }
VAR
  node, items_arr: ADRMEM;
BEGIN
  node := cJSON_CreateObject;
  AddBoolField(node, '__tuple__', TRUE);
  items_arr := cJSON_CreateArray;
  cJSON_AddItemToArray(items_arr, item1);
  cJSON_AddItemToArray(items_arr, item2);
  AddField(node, 'items', items_arr);
  MakeTupleNode := node;
END;

FUNCTION ParseType: ADRMEM;
VAR
  node, idx_range, elem_type, base_type, space_expr: ADRMEM;
  packed_flag, is_super: BOOLEAN;
  nm: Str255;
  fields_arr, names_arr, field_type, max_len_expr, param_expr, values_arr: ADRMEM;
  variants_arr, labels_arr, arm_fields_arr, arm_node, tag_type: ADRMEM;
  tag_name: Str255;
  has_tag: BOOLEAN;
  max_len: INTEGER;
  res_c: CINT;
BEGIN
  EnterTypeLevel;
  packed_flag := Match('PACKED');
  IF (CurKind = 'IDENTIFIER') AND (UpperStr(CurLex) = 'VECTOR') AND (NextKind = 'LBRACKET') THEN
  BEGIN
    { Contextual VECTOR type constructor, following the DEVICE precedent:
      recognized in type position by identifier text plus a one-token
      lookahead for '[', so a program using VECTOR as an identifier keeps
      working. The lane count is a full constant-expression node -- both
      later stages fold IntLiterals and CONST identifiers, nothing else.
      PACKED VECTOR is rejected here, the earliest point a diagnostic can
      fire. }
    IF packed_flag THEN
    BEGIN
      EPrint('Parser Error: PACKED VECTOR is not supported');
      exit(1);
    END;
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('LBRACKET');
    idx_range := ParseConstant;
    Expect('RBRACKET');
    Expect('OF');
    elem_type := ParseType;
    node := CreateTriviaNode('VectorType');
    AddField(node, 'lanes', idx_range);
    AddField(node, 'element_type', elem_type);
    AddBoolField(node, 'packed', FALSE);
    ParseType := node;
  END
  ELSE IF (CurKind = 'ARRAY') OR (CurKind = 'SUPER') THEN
  BEGIN
    is_super := (CurKind = 'SUPER');
    IF is_super THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      Expect('ARRAY');
    END
    ELSE
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('LBRACKET');
    idx_range := ParseIndexRange(is_super);
    Expect('RBRACKET');
    Expect('OF');
    elem_type := ParseType;
    node := CreateTriviaNode('ArrayType');
    AddField(node, 'index_range', idx_range);
    AddField(node, 'element_type', elem_type);
    AddBoolField(node, 'packed', packed_flag);
    AddBoolField(node, 'super', is_super);
    ParseType := node;
  END
  ELSE IF CurKind = 'RECORD' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    fields_arr := cJSON_CreateArray;
    { The fixed part ends at CASE, if there is a variant part. }
    WHILE (CurKind <> 'END') AND (CurKind <> 'CASE') DO
    BEGIN
      names_arr := ParseIdentListArr;
      Expect('COLON');
      field_type := ParseType;
      cJSON_AddItemToArray(fields_arr, MakeTupleNode(names_arr, field_type));
      IF CurKind = 'SEMICOLON' THEN
        pos := pos + 1
      ELSE
        BREAK;
    END;
    variants_arr := cJSON_CreateArray;
    tag_type := cJSON_CreateNull;
    has_tag := FALSE;
    tag_name := '';
    IF CurKind = 'CASE' THEN
    BEGIN
      BEGIN RelayTokenTrivia; pos := pos + 1; END;
      { A discriminant identifier is optional: CASE kind: INTEGER OF, or
        CASE INTEGER OF. }
      IF (CurKind = 'IDENTIFIER') AND (NextKind = 'COLON') THEN
      BEGIN
        has_tag := TRUE;
        tag_name := CurLex;
        BEGIN RelayTokenTrivia; pos := pos + 1; END;
        Expect('COLON');
      END;
      tag_type := ParseType;
      Expect('OF');
      WHILE CurKind <> 'END' DO
      BEGIN
        labels_arr := ParseCaseConstantList;
        Expect('COLON');
        Expect('LPAREN');
        arm_fields_arr := cJSON_CreateArray;
        WHILE CurKind <> 'RPAREN' DO
        BEGIN
          names_arr := ParseIdentListArr;
          Expect('COLON');
          field_type := ParseType;
          cJSON_AddItemToArray(arm_fields_arr, MakeTupleNode(names_arr, field_type));
          IF CurKind = 'SEMICOLON' THEN
            pos := pos + 1
          ELSE
            BREAK;
        END;
        Expect('RPAREN');
        arm_node := CreateTriviaNode('VariantArm');
        AddField(arm_node, 'labels', labels_arr);
        AddField(arm_node, 'fields', arm_fields_arr);
        cJSON_AddItemToArray(variants_arr, arm_node);
        IF CurKind = 'SEMICOLON' THEN
          pos := pos + 1
        ELSE
          BREAK;
      END;
    END;
    Expect('END');
    node := CreateTriviaNode('RecordType');
    AddField(node, 'fields', fields_arr);
    { Preserve the established RecordType JSON shape for ordinary records;
      native/Python typed-AST parity relies on it.  These fields are native
      extensions only when a variant part actually exists. }
    IF cJSON_GetArraySize(variants_arr) > 0 THEN
    BEGIN
      AddBoolField(node, 'has_tag', has_tag);
      AddStringField(node, 'tag_name', tag_name);
      AddField(node, 'tag_type', tag_type);
      AddField(node, 'variants', variants_arr);
    END;
    AddBoolField(node, 'packed', packed_flag);
    ParseType := node;
  END
  ELSE IF CurKind = 'SET' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('OF');
    base_type := ParseSetBase;
    node := CreateTriviaNode('SetType');
    AddField(node, 'base', base_type);
    ParseType := node;
  END
  ELSE IF CurKind = 'FILE' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('OF');
    elem_type := ParseType;
    node := CreateTriviaNode('FileType');
    AddField(node, 'element_type', elem_type);
    AddStringField(node, 'structure', 'BINARY');
    ParseType := node;
  END
  ELSE IF CurKind = 'LPAREN' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    values_arr := ParseIdentListArr;
    Expect('RPAREN');
    node := CreateTriviaNode('EnumType');
    AddField(node, 'values', values_arr);
    ParseType := node;
  END
  ELSE IF CurKind = 'POINTER' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    base_type := ParseType;
    node := CreateTriviaNode('PointerType');
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'POINTER');
    AddNullField(node, 'space');
    ParseType := node;
  END
  ELSE IF CurKind = 'ADR' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    Expect('OF');
    base_type := ParseType;
    node := CreateTriviaNode('PointerType');
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'ADR');
    AddNullField(node, 'space');
    ParseType := node;
  END
  ELSE IF CurKind = 'ADS' THEN
  BEGIN
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('PointerType');
    IF Match('LPAREN') THEN
    BEGIN
      space_expr := ParseExpression;
      Expect('RPAREN');
      AddField(node, 'space', space_expr);
    END
    ELSE
      AddNullField(node, 'space');
    Expect('OF');
    base_type := ParseType;
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'ADS');
    ParseType := node;
  END
  ELSE IF (CurKind = 'IDENTIFIER') AND (NextKind = 'RANGE') THEN
  BEGIN
    node := ParseSetBase;
    ParseType := node;
  END
  ELSE IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'CHAR_LITERAL') OR
          (CurKind = 'BOOLEAN_LITERAL') OR (CurKind = 'MINUS') OR
          (CurKind = 'PLUS') THEN
  BEGIN
    node := ParseSetBase;
    IF NodeType(node) <> 'SubrangeType' THEN
    BEGIN
      EPrint('Parser Error: expected subrange high bound');
      exit(1);
    END;
    ParseType := node;
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    nm := CurLex;
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    node := CreateTriviaNode('NamedType');
    AddStringField(node, 'name', nm);
    IF Match('LPAREN') THEN
    BEGIN
      param_expr := ParseConstant;
      Expect('RPAREN');
      { NamedType.param is a bare int or identifier-name, not the full
        constant-expression node, matching parser.py's unwrapping. }
      IF StringEqual(CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('__node_type__')))), 'IntLiteral') THEN
        { Not TRUNC: the capacity is a 32-bit quantity on both ends --
          cg_types reads this field back with GetInt -- and a capacity
          past 32767 (LSTRING(40000), say) would be poison through the
          16-bit INTEGER TRUNC produces. GetInt does the conversion in
          32 bits, exactly as codegen will on the other side. }
        AddIntField(node, 'param', GetInt(param_expr, 'value'))
      ELSE IF StringEqual(CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('__node_type__')))), 'Identifier') THEN
        AddStringField(node, 'param', CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('name')))))
      ELSE
        AddNullField(node, 'param');
    END
    ELSE
      AddNullField(node, 'param');
    ParseType := node;
  END
  ELSE IF (CurKind = 'INTEGER') OR (CurKind = 'REAL') OR (CurKind = 'BOOLEAN') OR
          (CurKind = 'CHAR') OR (CurKind = 'WORD') OR (CurKind = 'ADRMEM') THEN
  BEGIN
    node := CreateTriviaNode('BuiltinType');
    AddStringField(node, 'name', CurKind);
    BEGIN RelayTokenTrivia; pos := pos + 1; END;
    ParseType := node;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: expected type');
    exit(1);
  END;
  LeaveTypeLevel;
END;

BEGIN
  bound_expr_depth := 0;
END.
