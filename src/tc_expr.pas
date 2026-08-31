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
FUNCTION pas_double_to_int64(x: REAL): CLONG [C]; EXTERN;

FUNCTION CheckExpr(node: ADRMEM): INTEGER; FORWARD;

VAR
  expr_context_tk: INTEGER;

FUNCTION IsDeviceIndexName(name: Str255): BOOLEAN;
VAR
  upper_name: Str255;
BEGIN
  upper_name := UpperStr(name);
  IsDeviceIndexName :=
    (upper_name = 'THREADIDX_X') OR (upper_name = 'THREADIDX_Y') OR
    (upper_name = 'THREADIDX_Z') OR (upper_name = 'BLOCKIDX_X') OR
    (upper_name = 'BLOCKIDX_Y') OR (upper_name = 'BLOCKIDX_Z') OR
    (upper_name = 'BLOCKDIM_X') OR (upper_name = 'BLOCKDIM_Y') OR
    (upper_name = 'BLOCKDIM_Z') OR (upper_name = 'GRIDDIM_X') OR
    (upper_name = 'GRIDDIM_Y') OR (upper_name = 'GRIDDIM_Z');
END;

{ =============================== expressions ============================ }

PROCEDURE TagResolvedType(node: ADRMEM; type_name: Str255);
VAR
  tobj: ADRMEM;
BEGIN
  tobj := cJSON_CreateObject;
  AddStringField(tobj, '__type_system__', type_name);
  AddField(node, 'resolved_type', tobj);
END;

FUNCTION JsonIntegerValue(node: ADRMEM): INTEGER64;
BEGIN
  JsonIntegerValue := RETYPE(INTEGER64,
    pas_double_to_int64(GetReal(node, 'value')));
END;

FUNCTION FoldConstInt(node: ADRMEM; VAR folded_value: INTEGER64): BOOLEAN;
VAR
  nt, op, name, ch: Str255;
  left, right, quotient, remainder: INTEGER64;
  si: INTEGER32;
  args: ADRMEM;
BEGIN
  nt := NodeType(node);
  FoldConstInt := FALSE;
  IF nt = 'IntLiteral' THEN
  BEGIN
    folded_value := JsonIntegerValue(node);
    FoldConstInt := TRUE;
  END
  ELSE IF nt = 'CharLiteral' THEN
  BEGIN
    ch := GetStr(node, 'value');
    folded_value := ORD(ch[1]);
    FoldConstInt := TRUE;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    op := GetStr(node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS')) AND FoldConstInt(GetObj(node, 'operand'), folded_value) THEN
    BEGIN
      IF op = 'MINUS' THEN folded_value := 0 - folded_value;
      FoldConstInt := TRUE;
    END;
  END
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    op := GetStr(node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') OR
        (op = 'DIV') OR (op = 'MOD')) AND
       FoldConstInt(GetObj(node, 'left'), left) AND
       FoldConstInt(GetObj(node, 'right'), right) THEN
    BEGIN
      IF op = 'PLUS' THEN folded_value := left + right
      ELSE IF op = 'MINUS' THEN folded_value := left - right
      ELSE IF op = 'MUL' THEN folded_value := left * right
      ELSE IF right <> 0 THEN
      BEGIN
        quotient := left DIV right;
        remainder := left MOD right;
        IF (remainder <> 0) AND (((left < 0) AND (right > 0)) OR
           ((left > 0) AND (right < 0))) THEN quotient := quotient - 1;
        IF op = 'DIV' THEN folded_value := quotient
        ELSE folded_value := left - quotient * right;
        FoldConstInt := TRUE;
      END;
      IF (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') THEN
        FoldConstInt := TRUE;
    END;
  END
  ELSE IF (nt = 'Identifier') OR (nt = 'Designator') THEN
  BEGIN
    IF (nt = 'Identifier') OR (cJSON_GetArraySize(GetObj(node, 'selectors')) = 0) THEN
    BEGIN
      name := GetStr(node, 'name');
      si := LookupSymbol(name);
      IF (si <> 0) AND symbols[si].has_const_int THEN
      BEGIN
        folded_value := symbols[si].const_int;
        FoldConstInt := TRUE;
      END;
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    name := UpperStr(GetStr(node, 'name'));
    args := GetObj(node, 'args');
    IF ((name = 'ORD') OR (name = 'CHR') OR (name = 'SUCC') OR (name = 'PRED')) AND
       (cJSON_GetArraySize(args) = 1) AND
       FoldConstInt(cJSON_GetArrayItem(args, 0), folded_value) THEN
    BEGIN
      IF name = 'SUCC' THEN folded_value := folded_value + 1
      ELSE IF name = 'PRED' THEN folded_value := folded_value - 1;
      FoldConstInt := TRUE;
    END;
  END;
END;

FUNCTION IntegerTypeName(tk: INTEGER): Str255;
BEGIN
  IF tk = TK_INTEGER8 THEN IntegerTypeName := 'INTEGER8'
  ELSE IF tk = TK_INTEGER THEN IntegerTypeName := 'INTEGER'
  ELSE IF tk = TK_INTEGER32 THEN IntegerTypeName := 'INTEGER32'
  ELSE IF tk = TK_INTEGER64 THEN IntegerTypeName := 'INTEGER64'
  ELSE IF tk = TK_WORD8 THEN IntegerTypeName := 'WORD8'
  ELSE IF tk = TK_WORD THEN IntegerTypeName := 'WORD'
  ELSE IF tk = TK_WORD32 THEN IntegerTypeName := 'WORD32'
  ELSE IF tk = TK_WORD64 THEN IntegerTypeName := 'WORD64'
  ELSE IntegerTypeName := 'integer type';
END;

FUNCTION MaxWord16Value: INTEGER64;
BEGIN
  MaxWord16Value := 32767 * 2 + 1;
END;

FUNCTION MaxInteger32Value: INTEGER64;
VAR
  n: INTEGER64;
BEGIN
  { Build the limit from vintage-sized literals. This compiler source must
    bootstrap through implementations that context-check comparison operands
    as plain INTEGER. }
  n := 32767;
  n := n * 32767;
  n := n * 2;
  n := n + 32767;
  n := n + 32767;
  n := n + 32767;
  n := n + 32767;
  MaxInteger32Value := n + 1;
END;

FUNCTION MaxWord32Value: INTEGER64;
BEGIN
  MaxWord32Value := MaxInteger32Value * 2 + 1;
END;

FUNCTION IntegerConstantFits(tk: INTEGER; ival: INTEGER64): BOOLEAN;
BEGIN
  IF tk = TK_INTEGER8 THEN IntegerConstantFits := (ival >= -128) AND (ival <= 127)
  ELSE IF tk = TK_INTEGER THEN IntegerConstantFits := (ival >= -32767) AND (ival <= 32767)
  ELSE IF tk = TK_INTEGER32 THEN IntegerConstantFits :=
    (ival >= (-MaxInteger32Value - 1)) AND (ival <= MaxInteger32Value)
  ELSE IF tk = TK_INTEGER64 THEN IntegerConstantFits := TRUE
  ELSE IF tk = TK_WORD8 THEN IntegerConstantFits := (ival >= 0) AND (ival <= 255)
  ELSE IF tk = TK_WORD THEN
    { The manual converts a negative INTEGER constant to its 16-bit WORD bit
      pattern when a WORD context requires it. }
    IntegerConstantFits := (ival >= -32767) AND (ival <= MaxWord16Value)
  ELSE IF tk = TK_WORD32 THEN IntegerConstantFits := (ival >= 0) AND (ival <= MaxWord32Value)
  ELSE IF tk = TK_WORD64 THEN IntegerConstantFits := ival >= 0
  ELSE IntegerConstantFits := FALSE;
END;

PROCEDURE TagIntegerType(node: ADRMEM; tk: INTEGER);
VAR
  name: Str255;
BEGIN
  name := IntegerTypeName(tk);
  IF name = 'INTEGER' THEN name := 'IntegerType'
  ELSE IF name = 'WORD' THEN name := 'WordType'
  ELSE IF name = 'INTEGER8' THEN name := 'Integer8Type'
  ELSE IF name = 'INTEGER32' THEN name := 'Integer32Type'
  ELSE IF name = 'INTEGER64' THEN name := 'Integer64Type'
  ELSE IF name = 'WORD8' THEN name := 'Word8Type'
  ELSE IF name = 'WORD32' THEN name := 'Word32Type'
  ELSE IF name = 'WORD64' THEN name := 'Word64Type';
  TagResolvedType(node, name);
END;

FUNCTION NaturalIntegerType(ival: INTEGER64): INTEGER;
BEGIN
  IF (ival >= -32767) AND (ival <= 32767) THEN NaturalIntegerType := TK_INTEGER
  ELSE IF (ival >= 0) AND (ival <= MaxWord16Value) THEN NaturalIntegerType := TK_WORD
  ELSE IF active_features.wide_integers OR is_device_compiland THEN
  BEGIN
    IF (ival >= (-MaxInteger32Value - 1)) AND (ival <= MaxInteger32Value) THEN NaturalIntegerType := TK_INTEGER32
    ELSE IF ival >= 0 THEN NaturalIntegerType := TK_WORD32
    ELSE NaturalIntegerType := TK_INTEGER64;
  END
  ELSE BEGIN
    AddError('Integer constant is outside the vintage range -32767..65535');
    NaturalIntegerType := TK_UNKNOWN;
  END;
END;

FUNCTION CheckIntegerConstant(node: ADRMEM; ival: INTEGER64): INTEGER;
VAR
  tk: INTEGER;
BEGIN
  IF IsInteger(expr_context_tk) THEN tk := expr_context_tk
  ELSE tk := NaturalIntegerType(ival);
  IF (tk <> TK_UNKNOWN) AND NOT IntegerConstantFits(tk, ival) THEN
  BEGIN
    IF ival < 0 THEN
      AddError2('Negative integer constant out of range for ', IntegerTypeName(tk))
    ELSE
      AddError2('Positive integer constant out of range for ', IntegerTypeName(tk));
    CheckIntegerConstant := TK_UNKNOWN;
  END
  ELSE BEGIN
    IF tk <> TK_UNKNOWN THEN TagIntegerType(node, tk);
    CheckIntegerConstant := tk;
  END;
END;

FUNCTION CanAssign(target_tk, expr_tk: INTEGER): BOOLEAN;
VAR
  target_bits, expr_bits: INTEGER;
BEGIN
  target_bits := IntegerBits(target_tk);
  expr_bits := IntegerBits(expr_tk);
  IF (target_tk = TK_UNKNOWN) OR (expr_tk = TK_UNKNOWN) THEN
    CanAssign := TRUE
  ELSE IF target_tk = expr_tk THEN
    CanAssign := TRUE
  ELSE IF (target_tk = TK_REAL) AND IsSignedInteger(expr_tk) THEN
    CanAssign := TRUE
  ELSE IF IsInteger(target_tk) AND IsInteger(expr_tk) THEN
  BEGIN
    { Constant-sensitive signed-to-unsigned adaptation is handled by
      CheckExprForTarget. Nonconstant values must widen without losing range. }
    IF IsUnsignedInteger(target_tk) AND IsSignedInteger(expr_tk) THEN
      CanAssign := FALSE
    ELSE IF IsSignedInteger(target_tk) AND IsUnsignedInteger(expr_tk) THEN
      CanAssign := target_bits > expr_bits
    ELSE
      CanAssign := target_bits >= expr_bits;
  END
  ELSE IF (target_tk = TK_POINTER) AND (expr_tk = TK_POINTER) THEN
    CanAssign := TRUE
  ELSE
    CanAssign := FALSE;
END;

FUNCTION IntegerResultType(left_tk, right_tk: INTEGER): INTEGER;
VAR
  left_bits, right_bits: INTEGER;
BEGIN
  left_bits := IntegerBits(left_tk);
  right_bits := IntegerBits(right_tk);
  IF left_bits > right_bits THEN IntegerResultType := left_tk
  ELSE IF right_bits > left_bits THEN IntegerResultType := right_tk
  ELSE IF IsUnsignedInteger(left_tk) THEN IntegerResultType := left_tk
  ELSE IntegerResultType := right_tk;
END;

FUNCTION CheckExprForTarget(node: ADRMEM; target_tk: INTEGER): INTEGER;
VAR
  saved_context, result_tk: INTEGER;
  folded_value: INTEGER64;
  errors_before: INTEGER32;
BEGIN
  saved_context := expr_context_tk;
  IF IsInteger(target_tk) THEN expr_context_tk := target_tk
  ELSE expr_context_tk := TK_UNKNOWN;
  errors_before := nerrors;
  result_tk := CheckExpr(node);
  expr_context_tk := saved_context;
  IF IsInteger(target_tk) AND IsInteger(result_tk) AND FoldConstInt(node, folded_value) THEN
  BEGIN
    IF (nerrors = errors_before) AND NOT IntegerConstantFits(target_tk, folded_value) THEN
    BEGIN
      IF folded_value < 0 THEN
        AddError2('Negative integer constant out of range for ', IntegerTypeName(target_tk))
      ELSE
        AddError2('Positive integer constant out of range for ', IntegerTypeName(target_tk));
      result_tk := TK_UNKNOWN;
    END
    ELSE IF nerrors = errors_before THEN
      result_tk := target_tk;
  END;
  CheckExprForTarget := result_tk;
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
  tk, aux, aux2, itk, new_tk, new_aux, current_idx_tk: INTEGER;
  fi: INTEGER32;
  lane_ct: INTEGER;
  folded_value: INTEGER64;
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
  current_idx_tk := symbols[si].idx_tk;
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
      ELSE IF tk = TK_VECTOR THEN
      BEGIN
        { v[i]: lane access. The VECTOR [n] registration (tc_types) carries
          the scalar element kind in aux and the lane count in aux2; lanes
          are 0-based (LOWER is always 0). The result is that scalar, with
          no further element/aux to thread. A constant index outside
          0..n-1 is a compile-time error; a variable index is unchecked,
          matching arrays (no $INDEXCK machinery exists). }
        lane_ct := aux2;
        idx_expr := GetObj(sel, 'index_or_field');
        itk := CheckExpr(idx_expr);
        IF NOT IsOrdinal(itk) AND (itk <> TK_UNKNOWN) THEN
          AddError('Vector lane index must be an ordinal type');
        IF FoldConstInt(idx_expr, folded_value) THEN
          IF (folded_value < 0) OR (folded_value >= lane_ct) THEN
            AddError('Vector lane index out of range');
        tk := aux;
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
        IF current_idx_tk = TK_UNKNOWN THEN
          itk := CheckExpr(idx_expr)
        ELSE
          itk := CheckExprForTarget(idx_expr, current_idx_tk);
        IF NOT IsOrdinal(itk) AND (itk <> TK_UNKNOWN) THEN
          AddError('Array index must be an ordinal type');
        new_tk := aux;
        new_aux := aux2;
        tk := new_tk;
        { An LSTRING element/pointee carries its .LEN marker in the aux2 slot
          (a string never uses aux); route it back to aux2 so a[i].LEN and
          p^.LEN resolve instead of hitting the non-record selector error. }
        IF new_tk = TK_STRING THEN
        BEGIN
          aux := 0;
          aux2 := new_aux;
        END
        ELSE BEGIN
          aux := new_aux;
          aux2 := 0;
        END;
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
        { An LSTRING element/pointee carries its .LEN marker in the aux2 slot
          (a string never uses aux); route it back to aux2 so a[i].LEN and
          p^.LEN resolve instead of hitting the non-record selector error. }
        IF new_tk = TK_STRING THEN
        BEGIN
          aux := 0;
          aux2 := new_aux;
        END
        ELSE BEGIN
          aux := new_aux;
          aux2 := 0;
        END;
      END;
    END;
  END;
  last_designator_aux := aux;
  last_designator_aux2 := aux2;
  CheckDesignator := tk;
END;

FUNCTION CheckFuncCall(node: ADRMEM): INTEGER;
VAR
  name, orig_name: Str255;
  args_arr, warg: ADRMEM;
  nargs, i, si: INTEGER32;
  atk: INTEGER;
BEGIN
  orig_name := GetStr(node, 'name');
  name := UpperStr(orig_name);
  args_arr := GetObj(node, 'args');
  nargs := cJSON_GetArraySize(args_arr);
  IF name = 'DEVALLOC' THEN
  BEGIN
    IF is_device_compiland THEN
      AddError('DEVALLOC is host-only and cannot appear in DEVICE code');
    IF nargs <> 1 THEN
      AddError('DEVALLOC expects exactly one byte-count argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsInteger(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('DEVALLOC byte count must be an integer type');
    END;
    CheckFuncCall := TK_POINTER;
    RETURN;
  END;
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
      IF NOT IsInteger(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('CHR argument must be an integer type');
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
      IF NOT IsInteger(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('ODD argument must be an integer type');
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
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('SUCC/PRED argument must be an ordinal type');
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
      IF NOT IsNumeric(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('ABS/SQR argument must be numeric');
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
      IF NOT IsNumeric(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT argument must be numeric');
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
      IF NOT IsInteger(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('HIBYTE/LOBYTE argument must be an integer type');
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
    CheckFuncCall := TK_WORD8;
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
  IF (name = 'VSUM') OR (name = 'VPROD') OR (name = 'VMIN') OR (name = 'VMAX')
     OR (name = 'VANY') OR (name = 'VALL') THEN
  BEGIN
    { Horizontal reduction of one VECTOR to a scalar. This stage's coarse
      model carries no element kind through a call result; recover it only
      for the common case of a bare vector variable (a plain Identifier
      does not route through CheckDesignator). Anything fancier yields
      TK_UNKNOWN and codegen's table is the backstop. VANY/VALL always
      yield BOOLEAN. }
    IF nargs <> 1 THEN
    BEGIN
      AddError('A vector reduction takes exactly one VECTOR argument');
      CheckFuncCall := TK_UNKNOWN;
      RETURN;
    END;
    atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
    IF (atk <> TK_VECTOR) AND (atk <> TK_UNKNOWN) THEN
      AddError('A vector reduction requires a VECTOR argument');
    IF (name = 'VANY') OR (name = 'VALL') THEN
    BEGIN
      CheckFuncCall := TK_BOOLEAN;
      RETURN;
    END;
    IF NodeType(cJSON_GetArrayItem(args_arr, 0)) = 'Identifier' THEN
    BEGIN
      si := LookupSymbol(GetStr(cJSON_GetArrayItem(args_arr, 0), 'name'));
      IF (si <> 0) AND (symbols[si].tk = TK_VECTOR) THEN
      BEGIN
        IF symbols[si].aux = TK_BOOLEAN THEN
          AddError('VSUM/VPROD/VMIN/VMAX require a numeric VECTOR');
        CheckFuncCall := symbols[si].aux;
        RETURN;
      END;
    END;
    CheckFuncCall := TK_UNKNOWN;
    RETURN;
  END;
  IF name = 'VSPLAT' THEN
  BEGIN
    { VSPLAT(x, V): x a scalar, V a VECTOR TYPE NAME (a bare Identifier,
      resolved against the type table -- not CheckExpr'd as a value). This
      entry is mandatory: an untyped builtin falls through to the
      'Undefined function' arm below. The result kind is bare TK_VECTOR --
      this stage's model carries no lane count / element kind through a
      call result (codegen's table is the backstop, as for SETs). }
    IF nargs <> 2 THEN
      AddError('VSPLAT requires exactly two arguments (a scalar and a VECTOR type name)')
    ELSE
    BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      warg := cJSON_GetArrayItem(args_arr, 1);
      IF NodeType(warg) <> 'Identifier' THEN
        AddError('VSPLAT second argument must be a VECTOR type name')
      ELSE
      BEGIN
        si := LookupType(GetStr(warg, 'name'));
        IF (si = 0) OR (types[si].tk <> TK_VECTOR) THEN
          AddError('VSPLAT type argument is not a VECTOR type')
        ELSE IF (atk <> TK_UNKNOWN) AND NOT CanAssign(types[si].aux, atk) THEN
          AddError('VSPLAT scalar argument is not assignable to the vector element type');
      END;
    END;
    CheckFuncCall := TK_VECTOR;
    RETURN;
  END;
  IF name = 'VLOAD' THEN
  BEGIN
    { VLOAD(arr, i, V): arr an array, i an integer, V a VECTOR TYPE NAME
      (a bare Identifier resolved against the type table, like VSPLAT's).
      Result is bare TK_VECTOR -- codegen's table checks the element-type
      match and constant-index bounds. }
    IF nargs <> 3 THEN
      AddError('VLOAD requires exactly three arguments (an array, an index and a VECTOR type name)')
    ELSE
    BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_ARRAY) AND (atk <> TK_UNKNOWN) THEN
        AddError('VLOAD first argument must be an array');
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
      IF NOT IsInteger(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('VLOAD index must be an integer type');
      warg := cJSON_GetArrayItem(args_arr, 2);
      IF NodeType(warg) <> 'Identifier' THEN
        AddError('VLOAD third argument must be a VECTOR type name')
      ELSE
      BEGIN
        si := LookupType(GetStr(warg, 'name'));
        IF (si = 0) OR (types[si].tk <> TK_VECTOR) THEN
          AddError('VLOAD type argument is not a VECTOR type');
      END;
    END;
    CheckFuncCall := TK_VECTOR;
    RETURN;
  END;
  IF name = 'VSELECT' THEN
  BEGIN
    { VSELECT(m, a, b): m a mask VECTOR, a and b VECTORs; result is a's
      VECTOR type (bare TK_VECTOR in this coarse model -- codegen's table
      checks lane counts and that a, b agree). }
    IF nargs <> 3 THEN
      AddError('VSELECT requires exactly three arguments (a mask VECTOR and two VECTOR branches)')
    ELSE
      FOR i := 0 TO 2 DO
      BEGIN
        atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
        IF (atk <> TK_VECTOR) AND (atk <> TK_UNKNOWN) THEN
          AddError('VSELECT arguments must all be VECTOR values');
      END;
    CheckFuncCall := TK_VECTOR;
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
      IF i < symbols[si].nparams THEN
        atk := CheckExprForTarget(cJSON_GetArrayItem(args_arr, i),
                                  symbols[si].param_tk[i + 1])
      ELSE
        atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
      IF i < symbols[si].nparams THEN
        IF NOT CanAssign(symbols[si].param_tk[i + 1], atk) THEN
          AddError2('Argument type mismatch or implicit narrowing in call to ', orig_name);
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
  folded_value: INTEGER64;
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
    CheckExpr := CheckIntegerConstant(node, JsonIntegerValue(node))
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
    IF IsDeviceIndexName(name) THEN
    BEGIN
      IF NOT is_device_compiland THEN
      BEGIN
        AddError2('Device index builtin requires DEVICE code: ', name);
        CheckExpr := TK_UNKNOWN;
      END
      ELSE
        CheckExpr := TK_INTEGER32;
    END
    ELSE
    BEGIN
      si := LookupSymbol(name);
      IF si = 0 THEN
      BEGIN
        AddError('Undefined identifier');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE
        CheckExpr := symbols[si].tk;
    END;
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
    ELSE IF (lt = TK_VECTOR) OR (rt = TK_VECTOR) THEN
    BEGIN
      { Elementwise arithmetic/logic (and, later, comparison) on VECTORs.
        Both operands must be the same VECTOR type -- there is no
        scalar-to-vector promotion; write VSPLAT. The coarse tc type model
        returns a bare TK_VECTOR, so lane-count / element-kind agreement is
        verified in codegen (same split as SETs). }
      IF (lt <> TK_VECTOR) OR (rt <> TK_VECTOR) THEN
      BEGIN
        AddError('VECTOR operators require both operands to be the same VECTOR type (use VSPLAT for a scalar)');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR
              (op = 'GT') OR (op = 'GE') OR (op = 'AND') OR (op = 'OR') OR
              (op = 'XOR') OR (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') OR
              (op = 'SLASH') OR (op = 'DIV') OR (op = 'MOD') THEN
        CheckExpr := TK_VECTOR
      ELSE
      BEGIN
        AddError('Unsupported VECTOR operator');
        CheckExpr := TK_UNKNOWN;
      END;
    END
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
        CheckExpr := IntegerResultType(lt, rt);
    END;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    operand_node := GetObj(node, 'operand');
    op := GetStr(node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS')) AND
       (NodeType(operand_node) = 'IntLiteral') AND FoldConstInt(node, folded_value) THEN
    BEGIN
      ot := CheckIntegerConstant(node, folded_value);
      IF ot <> TK_UNKNOWN THEN TagIntegerType(operand_node, ot);
    END
    ELSE
      ot := CheckExpr(operand_node);
    IF op = 'NOT' THEN
    BEGIN
      IF ot = TK_VECTOR THEN
        CheckExpr := TK_VECTOR
      ELSE
      BEGIN
        IF (ot <> TK_BOOLEAN) AND (ot <> TK_UNKNOWN) THEN
          AddError('NOT requires a BOOLEAN operand');
        CheckExpr := TK_BOOLEAN;
      END;
    END
    ELSE
      CheckExpr := ot;
  END
  ELSE
    CheckExpr := TK_UNKNOWN;
  END;
  expr_depth := expr_depth - 1;
END;

BEGIN
END.
