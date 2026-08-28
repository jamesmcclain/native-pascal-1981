{ Expression and type parsing implementation. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
(*$INCLUDE:'ps_expr.inc'*)
IMPLEMENTATION OF ps_expr;
USES ps_base;

FUNCTION ParseExpression: ADRMEM; FORWARD;
FUNCTION ParseBooleanExpression: ADRMEM; FORWARD;
FUNCTION ParseSimpleExpression: ADRMEM; FORWARD;
FUNCTION ParseTerm: ADRMEM; FORWARD;
FUNCTION ParseFactor: ADRMEM; FORWARD;
FUNCTION ParseType: ADRMEM; FORWARD;
FUNCTION ParseConstant: ADRMEM; FORWARD;
FUNCTION ParseCaseConstant: ADRMEM; FORWARD;
FUNCTION ParseCaseConstantList: ADRMEM; FORWARD;

FUNCTION ParseIdentifier: ADRMEM;
VAR
  node: ADRMEM;
  name: Str255;
BEGIN
  node := CreateNode('Identifier');
  name := CurLex;
  Expect('IDENTIFIER');
  AddStringField(node, 'name', name);
  ParseIdentifier := node;
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
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'INDEX');
      AddField(sel_obj, 'index_or_field', ParseExpression);
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(selectors_arr, sel_obj);
        sel_obj := CreateNode('Selector');
        AddStringField(sel_obj, 'kind', 'INDEX');
        AddField(sel_obj, 'index_or_field', ParseExpression);
      END;
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
    ELSE IF CurKind = 'POINTER' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'DEREF');
      AddNullField(sel_obj, 'index_or_field');
      cJSON_AddItemToArray(selectors_arr, sel_obj);
    END;
  END;

  IF has_sel THEN
  BEGIN
    node := CreateNode('Designator');
    AddStringField(node, 'name', name);
    AddField(node, 'selectors', selectors_arr);
    ParseDesignatorRest := node;
  END
  ELSE
  BEGIN
    node := CreateNode('Identifier');
    AddStringField(node, 'name', name);
    ParseDesignatorRest := node;
  END;
END;

FUNCTION ParseDesignator: ADRMEM;
VAR
  node, selectors_arr, sel_obj: ADRMEM;
  name: Str255;
BEGIN
  node := CreateNode('Designator');
  name := CurLex;
  Expect('IDENTIFIER');
  AddStringField(node, 'name', name);
  selectors_arr := cJSON_CreateArray;

  WHILE (CurKind = 'LBRACKET') OR (CurKind = 'DOT') OR (CurKind = 'POINTER') DO
  BEGIN
    IF CurKind = 'LBRACKET' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'INDEX');
      AddField(sel_obj, 'index_or_field', ParseExpression);
      WHILE Match('COMMA') DO
      BEGIN
        cJSON_AddItemToArray(selectors_arr, sel_obj);
        sel_obj := CreateNode('Selector');
        AddStringField(sel_obj, 'kind', 'INDEX');
        AddField(sel_obj, 'index_or_field', ParseExpression);
      END;
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
    ELSE IF CurKind = 'POINTER' THEN
    BEGIN
      pos := pos + 1;
      sel_obj := CreateNode('Selector');
      AddStringField(sel_obj, 'kind', 'DEREF');
      AddNullField(sel_obj, 'index_or_field');
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

FUNCTION MakeBinOp(op_str: Str255; left, right: ADRMEM): ADRMEM;
VAR
  node: ADRMEM;
BEGIN
  node := CreateNode('BinOp');
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
BEGIN
  { Mirrors parser.py's parse_constant precedence exactly: an unsigned
    literal/identifier is tried first (no sign consumed here), and a leading
    +/- sign is only legal directly before INTEGER_LITERAL/REAL_LITERAL --
    e.g. -'A' must be rejected, not silently accepted. }
  IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    node := CreateNode('IntLiteral');
    { CurValueInt returns INTEGER32 (it holds a literal's full folded value),
      but AddIntField's value param is a plain INTEGER and the language has
      no implicit INTEGER32 -> INTEGER narrowing; RETYPE makes the
      deliberate truncation explicit. }
    AddIntField(node, 'value', RETYPE(INTEGER, CurValueInt()));
    Expect('INTEGER_LITERAL');
    ParseConstant := node;
  END
  ELSE IF CurKind = 'REAL_LITERAL' THEN
  BEGIN
    node := CreateNode('RealLiteral');
    val_str := CurLex;
    Expect('REAL_LITERAL');
    AddRealField(node, 'value', StrToRealVal(val_str));
    ParseConstant := node;
  END
  ELSE IF CurKind = 'CHAR_LITERAL' THEN
  BEGIN
    node := CreateNode('CharLiteral');
    val_str := CurValueStr;
    Expect('CHAR_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseConstant := node;
  END
  ELSE IF CurKind = 'STRING_LITERAL' THEN
  BEGIN
    node := CreateNode('StringLiteral');
    val_str := CurLex;
    Expect('STRING_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseConstant := node;
  END
  ELSE IF CurKind = 'BOOLEAN_LITERAL' THEN
  BEGIN
    node := CreateNode('BoolLiteral');
    val_str := CurLex;
    Expect('BOOLEAN_LITERAL');
    AddBoolField(node, 'value', StringEqual(UpperStr(val_str), 'TRUE'));
    ParseConstant := node;
  END
  ELSE IF CurKind = 'NIL' THEN
  BEGIN
    pos := pos + 1;
    ParseConstant := CreateNode('NilLiteral');
  END
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    val_str := CurLex;
    Expect('IDENTIFIER');
    IF (StringEqual(UpperStr(val_str), 'WRD') OR StringEqual(UpperStr(val_str), 'BYWORD')) AND
       (CurKind = 'LPAREN') THEN
    BEGIN
      pos := pos + 1;
      node := CreateNode('FuncCall');
      AddStringField(node, 'name', val_str);
      args_arr_const := cJSON_CreateArray;
      cJSON_AddItemToArray(args_arr_const, ParseConstant());
      WHILE CurKind = 'COMMA' DO
      BEGIN
        pos := pos + 1;
        cJSON_AddItemToArray(args_arr_const, ParseConstant());
      END;
      Expect('RPAREN');
      AddField(node, 'args', args_arr_const);
      ParseConstant := node;
    END
    ELSE
    BEGIN
      node := CreateNode('Identifier');
      AddStringField(node, 'name', val_str);
      ParseConstant := node;
    END;
  END
  ELSE IF (CurKind = 'PLUS') OR (CurKind = 'MINUS') THEN
  BEGIN
    sign_neg := (CurKind = 'MINUS');
    pos := pos + 1;
    IF CurKind = 'INTEGER_LITERAL' THEN
    BEGIN
      node := CreateNode('IntLiteral');
      { CurValueInt returns INTEGER32 (it holds a literal's full folded
        value), but AddIntField's value param is a plain INTEGER and the
        language has no implicit INTEGER32 -> INTEGER narrowing; RETYPE
        makes the deliberate truncation explicit. }
      IF sign_neg THEN
        AddIntField(node, 'value', -RETYPE(INTEGER, CurValueInt()))
      ELSE
        AddIntField(node, 'value', RETYPE(INTEGER, CurValueInt()));
      Expect('INTEGER_LITERAL');
      ParseConstant := node;
    END
    ELSE IF CurKind = 'REAL_LITERAL' THEN
    BEGIN
      node := CreateNode('RealLiteral');
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
    node := CreateNode('RangeExpr');
    AddField(node, 'low', e);
    AddField(node, 'high', high);
    ParseSetElement := node;
  END
  ELSE
    ParseSetElement := e;
END;

FUNCTION ParseFactor: ADRMEM;
VAR
  node, expr, args_arr, elements_arr: ADRMEM;
  val_str, name, kop: Str255;
  res_c: CINT;
BEGIN
  IF CurKind = 'NOT' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('UnaryOp');
    AddStringField(node, 'op', 'NOT');
    AddField(node, 'operand', ParseFactor);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'INTEGER_LITERAL' THEN
  BEGIN
    node := CreateNode('IntLiteral');
    { CurValueInt returns INTEGER32 (it holds a literal's full folded value),
      but AddIntField's value param is a plain INTEGER and the language has
      no implicit INTEGER32 -> INTEGER narrowing; RETYPE makes the
      deliberate truncation explicit. }
    AddIntField(node, 'value', RETYPE(INTEGER, CurValueInt()));
    Expect('INTEGER_LITERAL');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'REAL_LITERAL' THEN
  BEGIN
    node := CreateNode('RealLiteral');
    val_str := CurLex;
    Expect('REAL_LITERAL');
    AddRealField(node, 'value', StrToRealVal(val_str));
    ParseFactor := node;
  END
  ELSE IF CurKind = 'CHAR_LITERAL' THEN
  BEGIN
    node := CreateNode('CharLiteral');
    val_str := CurValueStr;
    Expect('CHAR_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'STRING_LITERAL' THEN
  BEGIN
    node := CreateNode('StringLiteral');
    val_str := CurLex;
    Expect('STRING_LITERAL');
    AddStringField(node, 'value', val_str);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'BOOLEAN_LITERAL' THEN
  BEGIN
    node := CreateNode('BoolLiteral');
    val_str := CurLex;
    Expect('BOOLEAN_LITERAL');
    AddBoolField(node, 'value', StringEqual(val_str, 'TRUE') OR StringEqual(val_str, 'true'));
    ParseFactor := node;
  END
  ELSE IF CurKind = 'NIL' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('NilLiteral');
    ParseFactor := node;
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
      node := CreateNode('RetypeExpr');
      AddStringField(node, 'type_id', val_str);
      AddField(node, 'expr', expr);
      AddField(node, 'selectors', cJSON_CreateArray);
      ParseFactor := node;
    END
    ELSE IF NextKind = 'LPAREN' THEN
    BEGIN
      pos := pos + 2;
      IF CurKind <> 'RPAREN' THEN
        args_arr := ParseActualParameterList
      ELSE
        args_arr := cJSON_CreateArray;
      Expect('RPAREN');
      node := CreateNode('FuncCall');
      AddStringField(node, 'name', name);
      AddField(node, 'args', args_arr);
      ParseFactor := node;
    END
    ELSE
    BEGIN
      pos := pos + 1;
      ParseFactor := ParseDesignatorRest(name);
    END;
  END
  ELSE IF CurKind = 'LPAREN' THEN
  BEGIN
    Expect('LPAREN');
    expr := ParseExpression;
    Expect('RPAREN');
    ParseFactor := expr;
  END
  ELSE IF CurKind = 'LBRACKET' THEN
  BEGIN
    pos := pos + 1;
    elements_arr := cJSON_CreateArray;
    IF CurKind <> 'RBRACKET' THEN
    BEGIN
      cJSON_AddItemToArray(elements_arr, ParseSetElement);
      WHILE Match('COMMA') DO
        cJSON_AddItemToArray(elements_arr, ParseSetElement);
    END;
    Expect('RBRACKET');
    node := CreateNode('SetConstructor');
    AddField(node, 'elements', elements_arr);
    AddNullField(node, 'type_name');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'ADR' THEN
  BEGIN
    { ADR <variable-identifier>: address-of a bare variable name. Unlike the
      ADR-as-type-flavor production in ParseType (`VAR p: ADR OF T`), this
      is the value-producing expression form -- the grammar takes only a
      bare identifier, no selector chain (matches the Python reference's
      AdrExpr AST node, which likewise carries just a name). }
    pos := pos + 1;
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateNode('AdrExpr');
    AddStringField(node, 'name', name);
    ParseFactor := node;
  END
  ELSE IF CurKind = 'SIZEOF' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    node := CreateNode('SizeofExpr');
    IF CurKind = 'IDENTIFIER' THEN
    BEGIN
      name := CurLex;
      pos := pos + 1;
      AddStringField(node, 'target', name);
    END
    ELSE
      AddField(node, 'target', ParseType);
    Expect('RPAREN');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'UPPER' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateNode('UpperExpr');
    AddStringField(node, 'name', name);
    { UPPER(p^): bound of the pointee -- for a heap super array this is the
      dynamic upper bound recorded by long-form NEW. Native codegen.pas
      rejects this deref form (no super arrays there yet), but parsing it
      is still correct regardless of what codegen later does with it. }
    AddBoolField(node, 'deref', Match('POINTER'));
    Expect('RPAREN');
    ParseFactor := node;
  END
  ELSE IF CurKind = 'LOWER' THEN
  BEGIN
    pos := pos + 1;
    Expect('LPAREN');
    name := CurLex;
    Expect('IDENTIFIER');
    node := CreateNode('LowerExpr');
    AddStringField(node, 'name', name);
    AddBoolField(node, 'deref', Match('POINTER'));
    Expect('RPAREN');
    ParseFactor := node;
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
      pos := pos + 1;
      left := MakeBinOp(op_str, left, ParseFactor);
      k := CurKind;
    END;
  END;
  ParseTerm := left;
END;

FUNCTION ParseSimpleExpression: ADRMEM;
VAR
  left: ADRMEM;
  sign_minus: BOOLEAN;
  op_str, k: Str255;
  un: ADRMEM;
BEGIN
  sign_minus := FALSE;
  IF CurKind = 'MINUS' THEN
  BEGIN
    sign_minus := TRUE;
    pos := pos + 1;
  END
  ELSE IF CurKind = 'PLUS' THEN
    pos := pos + 1;
  left := ParseTerm;
  IF sign_minus THEN
  BEGIN
    un := CreateNode('UnaryOp');
    AddStringField(un, 'op', 'MINUS');
    AddField(un, 'operand', left);
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
      pos := pos + 1;
      left := MakeBinOp(op_str, left, ParseTerm);
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
    pos := pos + 1;
    ParseExpression := MakeBinOp(op_str, left, ParseSimpleExpression);
  END
  ELSE
    ParseExpression := left;
  LeaveExprLevel;
END;

FUNCTION ParseBooleanExpression: ADRMEM;
VAR
  left: ADRMEM;
  op_str: Str255;
BEGIN
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
    node := CreateNode('RangeExpr');
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
BEGIN
  node := CreateNode('IndexRange');
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
      node := CreateNode('SubrangeType');
      AddField(node, 'low', low_e);
      AddField(node, 'high', high_e);
      AddNullField(node, 'host');
      ParseSetBase := node;
    END
    ELSE
    BEGIN
      nm := CurLex;
      Expect('IDENTIFIER');
      node := CreateNode('NamedType');
      AddStringField(node, 'name', nm);
      AddNullField(node, 'param');
      ParseSetBase := node;
    END;
  END
  ELSE IF (CurKind = 'INTEGER_LITERAL') OR (CurKind = 'CHAR_LITERAL') OR
          (CurKind = 'STRING_LITERAL') OR (CurKind = 'BOOLEAN_LITERAL') THEN
  BEGIN
    low_e := ParseConstant;
    IF CurKind = 'RANGE' THEN
    BEGIN
      pos := pos + 1;
      high_e := ParseConstant;
      node := CreateNode('SubrangeType');
      AddField(node, 'low', low_e);
      AddField(node, 'high', high_e);
      AddNullField(node, 'host');
      ParseSetBase := node;
    END
    ELSE
    BEGIN
      node := CreateNode('BuiltinType');
      AddStringField(node, 'name', 'INTEGER');
      ParseSetBase := node;
    END;
  END
  ELSE IF (CurKind = 'INTEGER') OR (CurKind = 'REAL') OR (CurKind = 'BOOLEAN') OR
          (CurKind = 'CHAR') OR (CurKind = 'WORD') OR (CurKind = 'ADRMEM') THEN
  BEGIN
    node := CreateNode('BuiltinType');
    AddStringField(node, 'name', CurKind);
    pos := pos + 1;
    ParseSetBase := node;
  END
  ELSE
  BEGIN
    EPrint('Parser Error: expected set base type');
    exit(1);
  END;
END;

FUNCTION MakeTupleNode(item1, item2: ADRMEM): ADRMEM;
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
  IF (CurKind = 'ARRAY') OR (CurKind = 'SUPER') THEN
  BEGIN
    is_super := (CurKind = 'SUPER');
    IF is_super THEN
    BEGIN
      pos := pos + 1;
      Expect('ARRAY');
    END
    ELSE
      pos := pos + 1;
    Expect('LBRACKET');
    idx_range := ParseIndexRange(is_super);
    Expect('RBRACKET');
    Expect('OF');
    elem_type := ParseType;
    node := CreateNode('ArrayType');
    AddField(node, 'index_range', idx_range);
    AddField(node, 'element_type', elem_type);
    AddBoolField(node, 'packed', packed_flag);
    AddBoolField(node, 'super', is_super);
    ParseType := node;
  END
  ELSE IF CurKind = 'RECORD' THEN
  BEGIN
    pos := pos + 1;
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
      pos := pos + 1;
      { A discriminant identifier is optional: CASE kind: INTEGER OF, or
        CASE INTEGER OF. }
      IF (CurKind = 'IDENTIFIER') AND (NextKind = 'COLON') THEN
      BEGIN
        has_tag := TRUE;
        tag_name := CurLex;
        pos := pos + 1;
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
        arm_node := CreateNode('VariantArm');
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
    node := CreateNode('RecordType');
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
    pos := pos + 1;
    Expect('OF');
    base_type := ParseSetBase;
    node := CreateNode('SetType');
    AddField(node, 'base', base_type);
    ParseType := node;
  END
  ELSE IF CurKind = 'FILE' THEN
  BEGIN
    pos := pos + 1;
    Expect('OF');
    elem_type := ParseType;
    node := CreateNode('FileType');
    AddField(node, 'element_type', elem_type);
    AddStringField(node, 'structure', 'BINARY');
    ParseType := node;
  END
  ELSE IF CurKind = 'LPAREN' THEN
  BEGIN
    pos := pos + 1;
    values_arr := ParseIdentListArr;
    Expect('RPAREN');
    node := CreateNode('EnumType');
    AddField(node, 'values', values_arr);
    ParseType := node;
  END
  ELSE IF CurKind = 'POINTER' THEN
  BEGIN
    pos := pos + 1;
    base_type := ParseType;
    node := CreateNode('PointerType');
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'POINTER');
    AddNullField(node, 'space');
    ParseType := node;
  END
  ELSE IF CurKind = 'ADR' THEN
  BEGIN
    pos := pos + 1;
    Expect('OF');
    base_type := ParseType;
    node := CreateNode('PointerType');
    AddField(node, 'base', base_type);
    AddStringField(node, 'flavor', 'ADR');
    AddNullField(node, 'space');
    ParseType := node;
  END
  ELSE IF CurKind = 'ADS' THEN
  BEGIN
    pos := pos + 1;
    node := CreateNode('PointerType');
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
  ELSE IF CurKind = 'IDENTIFIER' THEN
  BEGIN
    nm := CurLex;
    pos := pos + 1;
    node := CreateNode('NamedType');
    AddStringField(node, 'name', nm);
    IF Match('LPAREN') THEN
    BEGIN
      param_expr := ParseConstant;
      Expect('RPAREN');
      { NamedType.param is a bare int or identifier-name, not the full
        constant-expression node, matching parser.py's unwrapping. }
      IF StringEqual(CStrToStr255(cJSON_GetStringValue(cJSON_GetObjectItem(param_expr, MakeCStr('__node_type__')))), 'IntLiteral') THEN
        AddIntField(node, 'param', TRUNC(cJSON_GetNumberValue(cJSON_GetObjectItem(param_expr, MakeCStr('value')))))
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
    node := CreateNode('BuiltinType');
    AddStringField(node, 'name', CurKind);
    pos := pos + 1;
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
END.
