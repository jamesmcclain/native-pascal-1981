{ Expression checking implementation. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_types.inc'*)
(*$INCLUDE:'tc_expr.inc'*)
IMPLEMENTATION OF tc_expr;

FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;

FUNCTION CheckExpr(node: ADRMEM): INTEGER; FORWARD;

{ =============================== expressions ============================ }

PROCEDURE TagResolvedType(node: ADRMEM; type_name: Str255);
VAR
  tobj: ADRMEM;
BEGIN
  tobj := cJSON_CreateObject;
  AddStringField(tobj, '__type_system__', type_name);
  AddField(node, 'resolved_type', tobj);
END;

FUNCTION CanAssign(target_tk, expr_tk: INTEGER): BOOLEAN;
BEGIN
  IF (target_tk = TK_UNKNOWN) OR (expr_tk = TK_UNKNOWN) THEN
    CanAssign := TRUE
  ELSE IF target_tk = expr_tk THEN
    CanAssign := TRUE
  ELSE IF (target_tk = TK_REAL) AND (expr_tk = TK_INTEGER) THEN
    CanAssign := TRUE
  ELSE IF (target_tk = TK_WORD) AND (expr_tk = TK_INTEGER) THEN
    { The vintage "INTEGER constant changes to WORD" rule (manual). The
      Python reference only allows this for a *constant* INTEGER
      expression; this file, like codegen.pas's own TypesCompatibleForAssign,
      simplifies by allowing it for any INTEGER-typed expression, not just
      literals -- a documented, deliberate looseness, not an oversight. }
    CanAssign := TRUE
  ELSE IF (target_tk = TK_POINTER) AND (expr_tk = TK_POINTER) THEN
    CanAssign := TRUE
  ELSE
    CanAssign := FALSE;
END;

FUNCTION CheckDesignator(node: ADRMEM): INTEGER;
{ Walks the base identifier's selectors, threading a (tk, aux, aux2) triple
  along so a FIELD or INDEX selector applied right after a DEREF/INDEX can
  still resolve (aux2 carries the element/pointee's own aux -- see SymRec's
  aux2 doc comment). Only one level of nesting is tracked this way. }
VAR
  name: Str255;
  si: INTEGER32;
  sel_arr: ADRMEM;
  nsel, i: INTEGER32;
  sel, idx_expr: ADRMEM;
  skind, fname: Str255;
  tk, aux, aux2, itk, new_tk, new_aux: INTEGER;
  fi: INTEGER32;
BEGIN
  name := GetStr(node, 'name');
  si := LookupSymbol(name);
  IF si = 0 THEN
  BEGIN
    AddError('Undefined identifier');
    CheckDesignator := TK_UNKNOWN;
    RETURN;
  END;
  tk := symbols[si].tk;
  aux := symbols[si].aux;
  aux2 := symbols[si].aux2;
  sel_arr := GetObj(node, 'selectors');
  nsel := cJSON_GetArraySize(sel_arr);
  FOR i := 0 TO nsel - 1 DO
  BEGIN
    sel := cJSON_GetArrayItem(sel_arr, i);
    skind := GetStr(sel, 'kind');
    IF skind = 'FIELD' THEN
    BEGIN
      fname := UpperStr(CStrToStr255(cJSON_GetStringValue(GetObj(sel, 'index_or_field'))));
      IF (tk = TK_STRING) AND (aux2 = 1) THEN
      BEGIN
        { An LSTRING's only field: .LEN is its leading length byte, a CHAR
          (hence the ORD() around it at every use). Assignable, which is how
          a program truncates a string in place. A fixed STRING has no
          length byte and so no .LEN -- aux2 = 1 marks the LSTRING. }
        IF fname <> 'LEN' THEN
          AddError('LSTRING has no such field');
        tk := TK_CHAR;
        aux := 0;
        aux2 := 0;
      END
      ELSE IF tk <> TK_RECORD THEN
      BEGIN
        AddError('Field selector on non-record value');
        tk := TK_UNKNOWN;
        aux := 0;
        aux2 := 0;
      END
      ELSE BEGIN
        fname := CStrToStr255(cJSON_GetStringValue(GetObj(sel, 'index_or_field')));
        fi := LookupField(aux, fname);
        IF fi = 0 THEN
        BEGIN
          AddError('Unknown field');
          tk := TK_UNKNOWN;
          aux := 0;
          aux2 := 0;
        END
        ELSE BEGIN
          tk := fields[fi].ftk;
          aux := fields[fi].faux;
          aux2 := fields[fi].faux2;
        END;
      END;
    END
    ELSE IF skind = 'INDEX' THEN
    BEGIN
      IF tk = TK_STRING THEN
      BEGIN
        { s[i] on a STRING/LSTRING indexes its characters (Str255[0] is the
          length byte, matching this repository's own Str255 usage) --
          not array indexing, so there's no per-declaration element/aux to
          carry forward; the result is always a plain CHAR. }
        idx_expr := GetObj(sel, 'index_or_field');
        itk := CheckExpr(idx_expr);
        IF NOT IsOrdinal(itk) AND (itk <> TK_UNKNOWN) THEN
          AddError('String index must be an ordinal type');
        tk := TK_CHAR;
        aux := 0;
        aux2 := 0;
      END
      ELSE IF tk <> TK_ARRAY THEN
      BEGIN
        AddError('Index selector on non-array value');
        tk := TK_UNKNOWN;
        aux := 0;
        aux2 := 0;
      END
      ELSE BEGIN
        idx_expr := GetObj(sel, 'index_or_field');
        itk := CheckExpr(idx_expr);
        IF NOT IsOrdinal(itk) AND (itk <> TK_UNKNOWN) THEN
          AddError('Array index must be an ordinal type');
        new_tk := aux;
        new_aux := aux2;
        tk := new_tk;
        aux := new_aux;
        aux2 := 0;
      END;
    END
    ELSE IF skind = 'DEREF' THEN
    BEGIN
      IF tk = TK_FILE THEN
      BEGIN
        { F^: the file's buffer variable (the standard READ/WRITE-underlying
          "current component" model, manual ch.13) -- its type is the file's
          own element type, carried in aux exactly like a POINTER's pointee. }
        new_tk := aux;
        tk := new_tk;
        aux := 0;
        aux2 := 0;
      END
      ELSE IF tk <> TK_POINTER THEN
      BEGIN
        AddError('Dereference of non-pointer value');
        tk := TK_UNKNOWN;
        aux := 0;
        aux2 := 0;
      END
      ELSE BEGIN
        new_tk := aux;
        new_aux := aux2;
        tk := new_tk;
        aux := new_aux;
        aux2 := 0;
      END;
    END;
  END;
  last_designator_aux := aux;
  last_designator_aux2 := aux2;
  CheckDesignator := tk;
END;

FUNCTION CheckFuncCall(node: ADRMEM): INTEGER;
VAR
  name: Str255;
  args_arr, warg: ADRMEM;
  nargs, i, si: INTEGER32;
  atk: INTEGER;
BEGIN
  name := GetStr(node, 'name');
  args_arr := GetObj(node, 'args');
  nargs := cJSON_GetArraySize(args_arr);
  IF name = 'WRD' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('WRD requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('WRD argument must be an ordinal type');
    END;
    CheckFuncCall := TK_WORD;
    RETURN;
  END;
  IF name = 'BYWORD' THEN
  BEGIN
    IF nargs <> 2 THEN
      AddError('BYWORD requires exactly two arguments')
    ELSE
      FOR i := 0 TO nargs - 1 DO
      BEGIN
        atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
        IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
          AddError('BYWORD argument must be an ordinal type');
      END;
    CheckFuncCall := TK_WORD;
    RETURN;
  END;
  IF name = 'ORD' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('ORD requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('ORD argument must be an ordinal type');
    END;
    CheckFuncCall := TK_INTEGER;
    RETURN;
  END;
  IF name = 'CHR' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('CHR requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT CanAssign(TK_INTEGER, atk) THEN
        AddError('CHR argument must be INTEGER');
    END;
    CheckFuncCall := TK_CHAR;
    RETURN;
  END;
  IF (name = 'TRUNC') OR (name = 'ROUND') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('TRUNC/ROUND requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_REAL) AND (atk <> TK_UNKNOWN) THEN
        AddError('TRUNC/ROUND argument must be REAL');
    END;
    CheckFuncCall := TK_INTEGER;
    RETURN;
  END;
  IF name = 'ODD' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('ODD requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_UNKNOWN) THEN
        AddError('ODD argument must be INTEGER or WORD');
    END;
    CheckFuncCall := TK_BOOLEAN;
    RETURN;
  END;
  IF (name = 'SUCC') OR (name = 'PRED') THEN
  BEGIN
    IF nargs <> 1 THEN
    BEGIN
      AddError('SUCC/PRED requires exactly one argument');
      CheckFuncCall := TK_UNKNOWN;
    END
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_CHAR) AND (atk <> TK_ENUM) AND (atk <> TK_UNKNOWN) THEN
        AddError('SUCC/PRED argument must be INTEGER, WORD, CHAR, or an enumerated type');
      CheckFuncCall := atk;
    END;
    RETURN;
  END;
  IF (name = 'ABS') OR (name = 'SQR') THEN
  BEGIN
    IF nargs <> 1 THEN
    BEGIN
      AddError('ABS/SQR requires exactly one argument');
      CheckFuncCall := TK_UNKNOWN;
    END
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_REAL) AND (atk <> TK_UNKNOWN) THEN
        AddError('ABS/SQR argument must be INTEGER, WORD, or REAL');
      CheckFuncCall := atk;
    END;
    RETURN;
  END;
  IF (name = 'SQRT') OR (name = 'SIN') OR (name = 'COS') OR (name = 'LN') OR
     (name = 'EXP') OR (name = 'ARCTAN') OR (name = 'FLOAT') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_REAL) AND (atk <> TK_UNKNOWN) THEN
        AddError('SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT argument must be INTEGER, WORD, or REAL');
    END;
    CheckFuncCall := TK_REAL;
    RETURN;
  END;
  IF (name = 'HIBYTE') OR (name = 'LOBYTE') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('HIBYTE/LOBYTE requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_UNKNOWN) THEN
        AddError('HIBYTE/LOBYTE argument must be INTEGER or WORD');
    END;
    CheckFuncCall := TK_CHAR;
    RETURN;
  END;
  IF name = 'WRD8' THEN
  BEGIN
    IF NOT (active_features.wide_integers OR is_device_compiland) THEN
      AddError('WRD8 requires the extended dialect');
    IF nargs <> 1 THEN
      AddError('WRD8 requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('WRD8 argument must be an ordinal type');
    END;
    { typechecker.pas's coarse type model has no distinct WORD8 tag (see
      the header comment); codegen.pas resolves the real result type
      independently by re-walking the AST itself, so this tag is only
      used for this file's own downstream error-checking, same as WRD
      returning TK_WORD above. }
    CheckFuncCall := TK_WORD;
    RETURN;
  END;
  IF (name = 'EOF') OR (name = 'EOLN') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('EOF/EOLN requires exactly one argument')
    ELSE BEGIN
      warg := cJSON_GetArrayItem(args_arr, 0);
      IF NodeType(warg) <> 'Identifier' THEN
        AddError('EOF/EOLN argument must be a file variable')
      ELSE BEGIN
        si := LookupSymbol(GetStr(warg, 'name'));
        IF si = 0 THEN
          AddError('Undefined identifier')
        ELSE IF symbols[si].tk <> TK_FILE THEN
          AddError('EOF/EOLN argument must be a file variable')
        ELSE IF (name = 'EOLN') AND ((symbols[si].aux <> TK_CHAR) OR (symbols[si].aux2 <> 1)) THEN
          AddError('EOLN requires a TEXT file, not a binary FILE');
      END;
    END;
    CheckFuncCall := TK_BOOLEAN;
    RETURN;
  END;
  si := LookupSymbol(name);
  IF si = 0 THEN
  BEGIN
    AddError('Undefined function');
    FOR i := 0 TO nargs - 1 DO
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
    CheckFuncCall := TK_UNKNOWN;
    RETURN;
  END;
  { A [VARARGS] routine's declared parameters are only the fixed prefix, so
    MORE actuals than formals is legal there (and only there); every tail
    argument still has to be a well-formed expression, but has no formal to
    be assignment-compatible with. }
  IF (nargs <> symbols[si].nparams)
     AND NOT (symbols[si].is_vararg AND (nargs > symbols[si].nparams)) THEN
    AddError('Argument count mismatch')
  ELSE
    FOR i := 0 TO nargs - 1 DO
    BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
      IF i < symbols[si].nparams THEN
        IF NOT CanAssign(symbols[si].param_tk[i + 1], atk) THEN
          AddError('Argument type mismatch');
    END;
  CheckFuncCall := symbols[si].ret_tk;
END;

FUNCTION CheckExpr(node: ADRMEM): INTEGER;
VAR
  nt, name: Str255;
  si: INTEGER32;
  left_node, right_node, operand_node, type_node: ADRMEM;
  lt, rt, ot, op_kind, aux, aux2, idx_tk: INTEGER;
  op: Str255;
  elems_arr, elem_node: ADRMEM;
  n_elems, ei: INTEGER32;
BEGIN
  expr_depth := expr_depth + 1;
  IF expr_depth > MAX_EXPR_DEPTH THEN
  BEGIN
    AddError('expression too complex (nesting deeper than 64); try breaking it up with intermediate value assigns');
    CheckExpr := TK_UNKNOWN;
  END
  ELSE BEGIN
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN
  BEGIN
    TagResolvedType(node, 'IntegerType');
    CheckExpr := TK_INTEGER;
  END
  ELSE IF nt = 'RealLiteral' THEN
  BEGIN
    TagResolvedType(node, 'RealType');
    CheckExpr := TK_REAL;
  END
  ELSE IF nt = 'BoolLiteral' THEN CheckExpr := TK_BOOLEAN
  ELSE IF nt = 'CharLiteral' THEN CheckExpr := TK_CHAR
  ELSE IF nt = 'StringLiteral' THEN CheckExpr := TK_STRING
  ELSE IF nt = 'NilLiteral' THEN CheckExpr := TK_POINTER
  ELSE IF nt = 'SizeofExpr' THEN CheckExpr := TK_INTEGER
  ELSE IF nt = 'AdrExpr' THEN
  BEGIN
    { ADR <var>: address-of a bare variable. This stage's type model has no
      distinct ADRMEM tag or per-declaration pointer flavor/space (unlike
      codegen.pas's own richer table) -- TK_POINTER is the same coarse tag
      NilLiteral above already uses for every other pointer-shaped result. }
    si := LookupSymbol(GetStr(node, 'name'));
    IF si = 0 THEN
    BEGIN
      AddError('Undefined identifier');
      CheckExpr := TK_UNKNOWN;
    END
    ELSE
      CheckExpr := TK_POINTER;
  END
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    name := GetStr(node, 'name');
    si := LookupSymbol(name);
    IF si = 0 THEN
    BEGIN
      AddError('Undefined identifier');
      CheckExpr := TK_UNKNOWN;
    END
    ELSE
      CheckExpr := symbols[si].tk;
  END
  ELSE IF nt = 'SetConstructor' THEN
  BEGIN
    { Element/range-bound ordinal checking only; this v1 type-kind model has
      no way to carry a SET's declared base ordinal kind through CheckExpr's
      bare-tk return value (unlike codegen.pas's richer type table), so a
      mismatched base across elements (e.g. mixing CHAR and INTEGER) is not
      caught here -- codegen.pas is the enforcement backstop for that, same
      division of labor as elsewhere in this file (see the header comment). }
    elems_arr := GetObj(node, 'elements');
    n_elems := cJSON_GetArraySize(elems_arr);
    FOR ei := 0 TO n_elems - 1 DO
    BEGIN
      elem_node := cJSON_GetArrayItem(elems_arr, ei);
      IF NodeType(elem_node) = 'RangeExpr' THEN
      BEGIN
        lt := CheckExpr(GetObj(elem_node, 'low'));
        rt := CheckExpr(GetObj(elem_node, 'high'));
        IF (lt <> TK_UNKNOWN) AND NOT IsOrdinal(lt) THEN
          AddError('Set range bound must be an ordinal type');
        IF (rt <> TK_UNKNOWN) AND NOT IsOrdinal(rt) THEN
          AddError('Set range bound must be an ordinal type');
      END
      ELSE BEGIN
        ot := CheckExpr(elem_node);
        IF (ot <> TK_UNKNOWN) AND NOT IsOrdinal(ot) THEN
          AddError('Set element must be an ordinal type');
      END;
    END;
    CheckExpr := TK_SET;
  END
  ELSE IF nt = 'Designator' THEN
    CheckExpr := CheckDesignator(node)
  ELSE IF nt = 'FuncCall' THEN
    CheckExpr := CheckFuncCall(node)
  ELSE IF nt = 'RetypeExpr' THEN
  BEGIN
    { RETYPE(TypeName, expr) is a language construct, not a function call.
      Resolve its target through the normal NamedType path and still check
      the source expression. }
    ot := CheckExpr(GetObj(node, 'expr'));
    type_node := CreateNode('NamedType');
    AddStringField(type_node, 'name', GetStr(node, 'type_id'));
    ResolveTypeExpr(type_node, lt, aux, aux2, idx_tk);
    CheckExpr := lt;
  END
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    left_node := GetObj(node, 'left');
    right_node := GetObj(node, 'right');
    lt := CheckExpr(left_node);
    rt := CheckExpr(right_node);
    op := GetStr(node, 'op');
    IF (lt = TK_UNKNOWN) OR (rt = TK_UNKNOWN) THEN
      CheckExpr := TK_UNKNOWN
    ELSE IF (op = 'AND') OR (op = 'OR') OR (op = 'AND_THEN') OR (op = 'OR_ELSE') THEN
    BEGIN
      IF (lt <> TK_BOOLEAN) OR (rt <> TK_BOOLEAN) THEN
      BEGIN
        AddError('Boolean operator requires BOOLEAN operands');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE
        CheckExpr := TK_BOOLEAN;
    END
    ELSE IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE') THEN
    BEGIN
      IF NOT (IsNumeric(lt) AND IsNumeric(rt)) AND (lt <> rt) THEN
        AddError('Comparison operands are not comparable');
      CheckExpr := TK_BOOLEAN;
    END
    ELSE IF op = 'IN' THEN
    BEGIN
      IF NOT IsOrdinal(lt) THEN
        AddError('IN requires an ordinal left operand');
      IF rt <> TK_SET THEN
        AddError('IN requires a SET right operand');
      CheckExpr := TK_BOOLEAN;
    END
    ELSE IF (lt = TK_SET) OR (rt = TK_SET) THEN
    BEGIN
      { Set union/intersection/difference (PLUS/MINUS/MUL): both operands
        must be SET. Base-kind mismatch (e.g. SET OF CHAR + SET OF INTEGER)
        is not caught here -- see the SetConstructor case's comment on why
        this coarse model can't carry a SET's base ordinal kind. }
      IF (lt <> TK_SET) OR (rt <> TK_SET) THEN
      BEGIN
        AddError('Set operator requires SET operands');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE IF (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') THEN
        CheckExpr := TK_SET
      ELSE
      BEGIN
        AddError('Unsupported SET operator');
        CheckExpr := TK_UNKNOWN;
      END;
    END
    ELSE BEGIN
      { arithmetic: PLUS/MINUS/TIMES/DIVIDE/DIV/MOD. Pointer arithmetic
        (pointer +/- an ordinal offset, e.g. `src_buf + pos`) is a real
        pattern in this repository's own native sources' hand-rolled
        growable buffers, so a POINTER operand paired with a numeric one
        stays a POINTER rather than tripping the numeric-operands error. }
      IF (lt = TK_POINTER) AND IsNumeric(rt) THEN
        CheckExpr := TK_POINTER
      ELSE IF (rt = TK_POINTER) AND IsNumeric(lt) THEN
        CheckExpr := TK_POINTER
      ELSE IF NOT (IsNumeric(lt) AND IsNumeric(rt)) THEN
      BEGIN
        AddError('Arithmetic operator requires numeric operands');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE IF (lt = TK_REAL) OR (rt = TK_REAL) THEN
        CheckExpr := TK_REAL
      ELSE
        CheckExpr := TK_INTEGER;
    END;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    operand_node := GetObj(node, 'operand');
    ot := CheckExpr(operand_node);
    op := GetStr(node, 'op');
    IF op = 'NOT' THEN
    BEGIN
      IF (ot <> TK_BOOLEAN) AND (ot <> TK_UNKNOWN) THEN
        AddError('NOT requires a BOOLEAN operand');
      CheckExpr := TK_BOOLEAN;
    END
    ELSE BEGIN
      IF ((op = 'PLUS') OR (op = 'MINUS')) AND (NodeType(operand_node) = 'IntLiteral') THEN
        TagResolvedType(node, 'IntegerType');
      CheckExpr := ot;
    END;
  END
  ELSE
    CheckExpr := TK_UNKNOWN;
  END;
  expr_depth := expr_depth - 1;
END;

BEGIN
END.
