{ Statement checking implementation. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_types.inc'*)
(*$INCLUDE:'tc_expr.inc'*)
(*$INCLUDE:'tc_stmt.inc'*)
IMPLEMENTATION OF tc_stmt;

FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C]; EXTERN;

CONST
  MAX_ROUTINE_LABELS = 256;

VAR
  routine_labels: ARRAY [1..MAX_ROUTINE_LABELS] OF Str255;
  nroutine_labels: INTEGER32;

PROCEDURE CheckStmt(node: ADRMEM); FORWARD;

FUNCTION TcLabelKey(node: ADRMEM; VAR display: Str255): Str255;
{ Normalize a LabelStmt/GotoStmt 'label' field: a JSON number is a numeric
  label, and a JSON string is an identifier label matched case-insensitively. }
VAR
  item: ADRMEM;
  v: INTEGER64;
BEGIN
  item := GetObj(node, 'label');
  IF (item <> NIL) AND (cJSON_IsNumber(item) <> 0) THEN
  BEGIN
    v := GetInt(node, 'label');
    IF v < 0 THEN v := v + 65536;
    display := Int64Text(v);
    TcLabelKey := display;
  END
  ELSE
  BEGIN
    display := GetStr(node, 'label');
    TcLabelKey := UpperStr(display);
  END;
END;

PROCEDURE CollectRoutineLabels(stmt: ADRMEM); FORWARD;

PROCEDURE CollectRoutineLabelsArr(arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  IF arr <> NIL THEN
  BEGIN
    n := cJSON_GetArraySize(arr);
    FOR i := 0 TO n - 1 DO
      CollectRoutineLabels(cJSON_GetArrayItem(arr, i));
  END;
END;

PROCEDURE CollectRoutineLabels(stmt: ADRMEM);
{ Collect every LabelStmt target reachable within the current routine body
  (matching cg_stmt.pas CollectLabels), so GotoStmt can diagnose undefined
  or non-local labels with a source location (NEW-42). }
VAR
  nt, key, display: Str255;
  elements, el: ADRMEM;
  n, i: INTEGER32;
  found: BOOLEAN;
BEGIN
  IF stmt = NIL THEN RETURN;
  nt := NodeType(stmt);
  IF nt = 'CompoundStmt' THEN
    CollectRoutineLabelsArr(GetObj(stmt, 'stmts'))
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    CollectRoutineLabels(GetObj(stmt, 'then_branch'));
    CollectRoutineLabels(GetObjOrNil(stmt, 'else_branch'));
  END
  ELSE IF nt = 'WhileStmt' THEN
    CollectRoutineLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'RepeatStmt' THEN
    CollectRoutineLabelsArr(GetObj(stmt, 'body'))
  ELSE IF nt = 'ForStmt' THEN
    CollectRoutineLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'WithStmt' THEN
    CollectRoutineLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'CaseStmt' THEN
  BEGIN
    elements := GetObj(stmt, 'elements');
    n := cJSON_GetArraySize(elements);
    FOR i := 0 TO n - 1 DO
    BEGIN
      el := cJSON_GetArrayItem(elements, i);
      CollectRoutineLabels(GetObj(el, 'stmt'));
    END;
    CollectRoutineLabels(GetObjOrNil(stmt, 'otherwise'));
  END
  ELSE IF nt = 'LabelStmt' THEN
  BEGIN
    key := TcLabelKey(stmt, display);
    found := FALSE;
    FOR i := 1 TO nroutine_labels DO
      IF routine_labels[i] = key THEN found := TRUE;
    IF (NOT found) AND (nroutine_labels < MAX_ROUTINE_LABELS) THEN
    BEGIN
      nroutine_labels := nroutine_labels + 1;
      routine_labels[nroutine_labels] := key;
    END;
    CollectRoutineLabels(GetObj(stmt, 'stmt'));
  END;
END;

PROCEDURE CheckGotoStmt(node: ADRMEM);
{ Kept out of CheckStmtBody to preserve its stack headroom (CMP-65). }
VAR
  key, display: Str255;
  i: INTEGER32;
  found: BOOLEAN;
BEGIN
  key := TcLabelKey(node, display);
  found := FALSE;
  FOR i := 1 TO nroutine_labels DO
    IF routine_labels[i] = key THEN found := TRUE;
  IF NOT found THEN
    AddError2('GOTO to undefined label (routine-local only): ', display);
END;

PROCEDURE CheckUnrollHint(node: ADRMEM; loop_name: Str255);
VAR
  unroll_node: ADRMEM;
BEGIN
  unroll_node := GetObjOrNil(node, 'unroll');
  IF unroll_node <> NIL THEN
  BEGIN
    IF NOT (active_features.tuning_hints OR is_device_compiland) THEN
      AddError2('{$UNROLL} requires the extended dialect on ', loop_name)
    ELSE IF GetInt(node, 'unroll') < 1 THEN
      AddError('{$UNROLL} count must be a positive integer');
  END;
END;

{ =============================== statements ============================= }

PROCEDURE CheckCompoundOrStmt(node: ADRMEM);
VAR
  nt: Str255;
  stmts_arr: ADRMEM;
  n, i: INTEGER32;
BEGIN
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    IF nt = 'CompoundStmt' THEN
    BEGIN
      stmts_arr := GetObj(node, 'stmts');
      n := cJSON_GetArraySize(stmts_arr);
      FOR i := 0 TO n - 1 DO
        CheckStmt(cJSON_GetArrayItem(stmts_arr, i));
    END
    ELSE
      CheckStmt(node);
  END;
END;

PROCEDURE CheckStmtList(arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  n := cJSON_GetArraySize(arr);
  FOR i := 0 TO n - 1 DO
    CheckStmt(cJSON_GetArrayItem(arr, i));
END;

PROCEDURE CheckRoutineBody(arr: ADRMEM);
BEGIN
  nroutine_labels := 0;
  CollectRoutineLabelsArr(arr);
  CheckStmtList(arr);
  nroutine_labels := 0;
END;

FUNCTION IsAddressLikeType(tk: INTEGER): BOOLEAN;
BEGIN
  IsAddressLikeType := (tk = TK_POINTER) OR (tk = TK_ARRAY) OR
                       (tk = TK_RECORD) OR (tk = TK_STRING);
END;

FUNCTION IsHostDeviceIntrinsic(name: Str255): BOOLEAN;
BEGIN
  IsHostDeviceIntrinsic := (name = 'DEVCOPYTO') OR
    (name = 'DEVCOPYFROM') OR (name = 'DEVFREE') OR (name = 'LAUNCH');
END;

PROCEDURE CheckHostDeviceIntrinsic(node: ADRMEM; pname: Str255);
VAR
  args_arr, warg: ADRMEM;
  nargs, i, start_arg, si: INTEGER32;
  cond_tk, expr_tk: INTEGER;
BEGIN
  args_arr := GetObj(node, 'args');
  nargs := cJSON_GetArraySize(args_arr);
  IF (pname = 'DEVCOPYTO') OR (pname = 'DEVCOPYFROM') THEN
  BEGIN
    IF is_device_compiland THEN
      AddError2('Host-only procedure cannot appear in DEVICE code: ', pname);
    IF nargs <> 3 THEN
      AddError2('Procedure expects exactly three arguments: ', pname)
    ELSE BEGIN
      cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (cond_tk <> TK_UNKNOWN) AND NOT IsAddressLikeType(cond_tk) THEN
        AddError2('Argument 1 must be a device handle or buffer address: ', pname);
      cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
      IF (cond_tk <> TK_UNKNOWN) AND NOT IsAddressLikeType(cond_tk) THEN
        AddError2('Argument 2 must be a device handle or buffer address: ', pname);
      cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 2));
      IF (cond_tk <> TK_UNKNOWN) AND NOT IsInteger(cond_tk) THEN
        AddError2('Byte count must be an integer type: ', pname);
    END;
  END
  ELSE IF pname = 'DEVFREE' THEN
  BEGIN
    IF is_device_compiland THEN
      AddError('DEVFREE is host-only and cannot appear in DEVICE code');
    IF nargs <> 1 THEN
      AddError('DEVFREE expects exactly one device-handle argument')
    ELSE BEGIN
      cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (cond_tk <> TK_UNKNOWN) AND NOT IsAddressLikeType(cond_tk) THEN
        AddError('DEVFREE argument must be a device handle');
    END;
  END
  ELSE BEGIN
    IF is_device_compiland THEN
      AddError('LAUNCH is host-only and cannot appear in DEVICE code');
    IF nargs < 1 THEN
      AddError('LAUNCH expects at least a kernel identifier')
    ELSE BEGIN
      warg := cJSON_GetArrayItem(args_arr, 0);
      IF NodeType(warg) <> 'Identifier' THEN
        AddError('LAUNCH first argument must be a kernel identifier')
      ELSE BEGIN
        si := LookupSymbol(GetStr(warg, 'name'));
        IF si = 0 THEN
          AddError2('LAUNCH cannot resolve kernel procedure: ', GetStr(warg, 'name'))
        ELSE IF symbols[si].kind <> 'PROC' THEN
          AddError2('LAUNCH kernel identifier is not a procedure: ', GetStr(warg, 'name'))
        ELSE BEGIN
          start_arg := nargs - 1 - symbols[si].nparams;
          IF (start_arg <> 2) AND (start_arg <> 6) THEN
            AddError('LAUNCH expects two or six geometry values plus the kernel arguments')
          ELSE BEGIN
            FOR i := 1 TO start_arg DO
            BEGIN
              cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
              IF (cond_tk <> TK_UNKNOWN) AND NOT IsInteger(cond_tk) THEN
                AddError('LAUNCH geometry dimension must be an integer type');
            END;
            start_arg := start_arg + 1;
            FOR i := 0 TO symbols[si].nparams - 1 DO
            BEGIN
              expr_tk := CheckExprForSetTarget(cJSON_GetArrayItem(args_arr, start_arg + i),
                symbols[si].param_tk[i + 1], symbols[si].param_set_sem_base[i + 1]);
              IF (symbols[si].param_tk[i + 1] = TK_POINTER) AND
                 IsAddressLikeType(expr_tk) THEN
                BEGIN END
              ELSE IF NOT CanAssign(symbols[si].param_tk[i + 1], expr_tk) THEN
                AddError2('Kernel argument type mismatch in LAUNCH call to ',
                          GetStr(warg, 'name'));
            END;
          END;
        END;
      END;
    END;
  END;
END;

FUNCTION IsDeviceSyncIntrinsic(name: Str255): BOOLEAN;
{ Case-sensitive, matching every other name in this ProcCallStmt dispatch
  chain (WRITELN, NEW, IsHostDeviceIntrinsic's DEVCOPYTO/LAUNCH/etc.) --
  a deliberate deviation from the manual's general case-insensitivity for
  predeclared identifiers, not a gap to close against the reference. }
BEGIN
  IsDeviceSyncIntrinsic := (name = 'SYNCTHREADS');
END;

PROCEDURE CheckDeviceSyncIntrinsic(node: ADRMEM; pname: Str255);
VAR
  args_arr: ADRMEM;
  nargs, i: INTEGER32;
  cond_tk: INTEGER;
BEGIN
  args_arr := GetObj(node, 'args');
  nargs := cJSON_GetArraySize(args_arr);
  IF NOT is_device_compiland THEN
    AddError2('Device synchronization builtin requires DEVICE code: ', pname)
  ELSE IF nargs <> 0 THEN
    AddError2('Procedure expects no arguments: ', pname);
  FOR i := 0 TO nargs - 1 DO
    cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
END;

PROCEDURE CheckCaseLabel(label_node: ADRMEM; sel_tk, sel_sem: INTEGER);
{ One CASE label constant, checked against the selector the same way a FOR
  bound is checked against the loop variable: CheckExprForTarget gives a
  bare integer literal the selector's own width -- so `CASE i32 OF 1:` is
  not a spurious INTEGER-vs-INTEGER32 mismatch -- and CanAssign then holds
  the pair to the rule an assignment to the selector would obey. }
VAR
  label_tk: INTEGER;
BEGIN
  IF NodeType(label_node) = 'RangeExpr' THEN
  BEGIN
    CheckCaseLabel(GetObj(label_node, 'low'), sel_tk, sel_sem);
    CheckCaseLabel(GetObj(label_node, 'high'), sel_tk, sel_sem);
  END
  ELSE
  BEGIN
    label_tk := CheckExprForTarget(label_node, sel_tk);
    IF NOT CanAssign(sel_tk, label_tk) THEN
      AddError('CASE label type is incompatible with the selector type')
    { sel_sem is the selector's enumeration identity, when known. }
    ELSE IF (sel_tk = TK_ENUM) AND (label_tk = TK_ENUM) AND
            SemanticBasesConflict(sel_sem, last_sem_scalar_base) THEN
      AddError('CASE label is of a different enumeration type than the selector');
  END;
END;

PROCEDURE CheckCaseStmt(node: ADRMEM);
{ CASE was previously absent from CheckStmt's dispatch entirely: the
  selector, the labels and -- worse -- every case body went unchecked, and
  the first diagnostic for an ill-typed CASE came from CodegenCaseStmt's
  AbortWith, one error at a time and with no source context. The selector
  rule enforced here is codegen's: an ordinal value whose labels all adapt
  to its own type. }
VAR
  elements_arr, constants_arr, el, otherwise_stmt: ADRMEM;
  sel_tk, sel_sem: INTEGER;
  n, i, nc, ci: INTEGER32;
BEGIN
  sel_tk := CheckExpr(GetObj(node, 'expr'));
  sel_sem := last_sem_scalar_base;
  IF NOT IsOrdinal(sel_tk) AND (sel_tk <> TK_UNKNOWN) THEN
  BEGIN
    AddError('CASE selector must be an ordinal type');
    { Labels checked against an unusable selector would only add noise. }
    sel_tk := TK_UNKNOWN;
  END;
  elements_arr := GetObj(node, 'elements');
  n := cJSON_GetArraySize(elements_arr);
  FOR i := 0 TO n - 1 DO
  BEGIN
    el := cJSON_GetArrayItem(elements_arr, i);
    constants_arr := GetObj(el, 'constants');
    nc := cJSON_GetArraySize(constants_arr);
    FOR ci := 0 TO nc - 1 DO
      CheckCaseLabel(cJSON_GetArrayItem(constants_arr, ci), sel_tk, sel_sem);
    CheckCompoundOrStmt(GetObjOrNil(el, 'stmt'));
  END;
  otherwise_stmt := GetObjOrNil(node, 'otherwise');
  IF otherwise_stmt <> NIL THEN
    CheckCompoundOrStmt(otherwise_stmt);
END;

PROCEDURE CheckNewDispose(args_arr: ADRMEM; pname: Str255);
{ Kept out of CheckStmt so its recursive frame stays small (tests/corpus/depth.sh). }
VAR
  nargs, si: INTEGER32;
  warg: ADRMEM;
  cond_tk: INTEGER;
BEGIN
  nargs := cJSON_GetArraySize(args_arr);
  { Mirrors codegen.pas's own arity/shape checks (its NEW/DISPOSE case
    is the only place this dialect's short-form allocation is actually
    lowered) so a well-typed NEW/DISPOSE call reaches codegen instead
    of being rejected here first as "Undefined procedure" -- this file
    previously had no handling of either name at all. NEW's second
    (SUPER ARRAY upper-bound) argument isn't modeled here -- this file
    has no is_super concept -- so it's checked leniently, same as
    CONCAT below: codegen itself decides whether a second argument is
    actually required or accepted for a given pointee type. }
  IF is_device_compiland THEN
    AddError2('Dynamic memory allocation is not supported in DEVICE code: ', pname);
  IF ((pname = 'DISPOSE') AND (nargs <> 1)) OR
     ((pname = 'NEW') AND (nargs <> 1) AND (nargs <> 2)) THEN
    AddError('Argument count mismatch')
  ELSE BEGIN
    warg := cJSON_GetArrayItem(args_arr, 0);
    IF NodeType(warg) = 'Designator' THEN
    BEGIN
      { A selected pointer such as q^.next or a[i]. }
      cond_tk := CheckDesignator(warg);
      IF (cond_tk <> TK_POINTER) AND (cond_tk <> TK_UNKNOWN) THEN
        AddError('NEW/DISPOSE argument must be a POINTER variable')
      ELSE IF (cond_tk = TK_POINTER) AND (last_designator_write_kind <> WRITABLE_OK) THEN
        AddError('NEW/DISPOSE argument must be a writable POINTER variable');
    END
    ELSE IF NodeType(warg) <> 'Identifier' THEN
      AddError('NEW/DISPOSE argument must be a pointer variable')
    ELSE BEGIN
      si := LookupSymbol(GetStr(warg, 'name'));
      IF si = 0 THEN
        AddUndefinedIdentifier(warg)
      ELSE IF symbols[si].tk <> TK_POINTER THEN
        AddError('NEW/DISPOSE argument must be a POINTER variable')
      ELSE IF (symbols[si].kind <> 'VAR') OR symbols[si].is_const_param THEN
        AddError('NEW/DISPOSE argument must be a writable POINTER variable');
    END;
    IF nargs = 2 THEN
      cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
  END;
END;

PROCEDURE CheckCopystr(args_arr: ADRMEM);
{ COPYSTR(CONST S: STRING; VAR D: STRING) into a bare fixed STRING variable,
  including type aliases and formals; aux2 = 0 excludes LSTRING. One-character
  literals adapt as strings, not arbitrary CHARs. }
VAR
  arg: ADRMEM;
  tk: INTEGER;
  si: INTEGER32;
BEGIN
  IF cJSON_GetArraySize(args_arr) <> 2 THEN
    AddError('COPYSTR expects exactly two arguments (S, D)')
  ELSE
  BEGIN
    arg := cJSON_GetArrayItem(args_arr, 0);
    tk := CheckExpr(arg);
    IF (tk <> TK_STRING) AND (tk <> TK_UNKNOWN) AND
       (NodeType(arg) <> 'CharLiteral') THEN
      AddError('COPYSTR source must be STRING or LSTRING');
    arg := cJSON_GetArrayItem(args_arr, 1);
    IF NodeType(arg) <> 'Identifier' THEN
      AddError('COPYSTR destination must be a bare STRING variable')
    ELSE
    BEGIN
      si := LookupSymbol(GetStr(arg, 'name'));
      IF si = 0 THEN
        AddUndefinedIdentifier(arg)
      ELSE IF (symbols[si].kind <> 'VAR') OR symbols[si].is_const_param OR
              (symbols[si].tk <> TK_STRING) OR (symbols[si].aux2 <> 0) THEN
        AddError('COPYSTR destination must be a bare STRING variable');
    END;
  END;
END;

PROCEDURE CheckInsert(args_arr: ADRMEM);
{ INSERT(CONST S: STRING; VAR D: LSTRING; I: INTEGER) into a bare LSTRING
  variable, including type aliases and formals; aux2 = 1 marks LSTRING.
  One-character literals adapt as strings, not arbitrary CHARs. }
VAR
  arg: ADRMEM;
  tk: INTEGER;
  si: INTEGER32;
BEGIN
  IF cJSON_GetArraySize(args_arr) <> 3 THEN
    AddError('INSERT expects exactly three arguments (S, D, I)')
  ELSE
  BEGIN
    arg := cJSON_GetArrayItem(args_arr, 0);
    tk := CheckExpr(arg);
    IF (tk <> TK_STRING) AND (tk <> TK_UNKNOWN) AND
       (NodeType(arg) <> 'CharLiteral') THEN
      AddError('INSERT source must be STRING or LSTRING');
    arg := cJSON_GetArrayItem(args_arr, 1);
    IF NodeType(arg) <> 'Identifier' THEN
      AddError('INSERT destination must be a bare LSTRING variable')
    ELSE
    BEGIN
      si := LookupSymbol(GetStr(arg, 'name'));
      IF si = 0 THEN
        AddUndefinedIdentifier(arg)
      ELSE IF (symbols[si].kind <> 'VAR') OR symbols[si].is_const_param OR
              (symbols[si].tk <> TK_STRING) OR (symbols[si].aux2 <> 1) THEN
        AddError('INSERT destination must be a bare LSTRING variable');
    END;
    tk := CheckExprForTarget(cJSON_GetArrayItem(args_arr, 2), TK_INTEGER);
    IF NOT CanAssign(TK_INTEGER, tk) THEN
      AddError('INSERT position must be INTEGER');
  END;
END;

PROCEDURE CheckDelete(args_arr: ADRMEM);
{ DELETE(VAR D: LSTRING; I, L: INTEGER) on a bare LSTRING variable, including
  type aliases and formals; aux2 = 1 marks LSTRING. }
VAR
  arg: ADRMEM;
  tk: INTEGER;
  si: INTEGER32;
BEGIN
  IF cJSON_GetArraySize(args_arr) <> 3 THEN
    AddError('DELETE expects exactly three arguments (D, I, L)')
  ELSE
  BEGIN
    arg := cJSON_GetArrayItem(args_arr, 0);
    IF NodeType(arg) <> 'Identifier' THEN
      AddError('DELETE destination must be a bare LSTRING variable')
    ELSE
    BEGIN
      si := LookupSymbol(GetStr(arg, 'name'));
      IF si = 0 THEN
        AddUndefinedIdentifier(arg)
      ELSE IF (symbols[si].kind <> 'VAR') OR symbols[si].is_const_param OR
              (symbols[si].tk <> TK_STRING) OR (symbols[si].aux2 <> 1) THEN
        AddError('DELETE destination must be a bare LSTRING variable');
    END;
    tk := CheckExprForTarget(cJSON_GetArrayItem(args_arr, 1), TK_INTEGER);
    IF NOT CanAssign(TK_INTEGER, tk) THEN
      AddError('DELETE position must be INTEGER');
    tk := CheckExprForTarget(cJSON_GetArrayItem(args_arr, 2), TK_INTEGER);
    IF NOT CanAssign(TK_INTEGER, tk) THEN
      AddError('DELETE count must be INTEGER');
  END;
END;

PROCEDURE CheckCopylst(args_arr: ADRMEM);
{ Native COPYLST initially supports the backend's bare destination seam.
  aux2 distinguishes LSTRING from fixed STRING, including type aliases and
  formals. One-character literals adapt as strings, not arbitrary CHARs. }
VAR
  arg: ADRMEM;
  tk: INTEGER;
  si: INTEGER32;
BEGIN
  IF cJSON_GetArraySize(args_arr) <> 2 THEN
    AddError('COPYLST expects exactly two arguments (S, D)')
  ELSE
  BEGIN
    arg := cJSON_GetArrayItem(args_arr, 0);
    tk := CheckExpr(arg);
    IF (tk <> TK_STRING) AND (tk <> TK_UNKNOWN) AND
       (NodeType(arg) <> 'CharLiteral') THEN
      AddError('COPYLST source must be STRING or LSTRING');
    arg := cJSON_GetArrayItem(args_arr, 1);
    IF NodeType(arg) <> 'Identifier' THEN
      AddError('COPYLST destination must be a bare LSTRING variable')
    ELSE
    BEGIN
      si := LookupSymbol(GetStr(arg, 'name'));
      IF si = 0 THEN
        AddUndefinedIdentifier(arg)
      ELSE IF (symbols[si].kind <> 'VAR') OR symbols[si].is_const_param OR
              (symbols[si].tk <> TK_STRING) OR (symbols[si].aux2 <> 1) THEN
        AddError('COPYLST destination must be a bare LSTRING variable');
    END;
  END;
END;

FUNCTION WriteArrayElemTk(expr: ADRMEM): INTEGER;
{ Element type kind of an expression CheckExpr just typed as TK_ARRAY, for
  distinguishing a writable one-dimensional ARRAY OF CHAR from an array of
  non-CHAR (including an array of CHAR arrays, CMP-26r). }
VAR
  nt: Str255;
  si: INTEGER32;
BEGIN
  WriteArrayElemTk := TK_UNKNOWN;
  nt := NodeType(expr);
  IF nt = 'Designator' THEN
    WriteArrayElemTk := last_designator_aux
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    si := LookupSymbol(GetStr(expr, 'name'));
    IF si <> 0 THEN
    BEGIN
      IF symbols[si].kind = 'FUNC' THEN
        WriteArrayElemTk := symbols[si].ret_aux
      ELSE
        WriteArrayElemTk := symbols[si].aux;
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    si := LookupSymbol(GetStr(expr, 'name'));
    IF si <> 0 THEN
      WriteArrayElemTk := symbols[si].ret_aux;
  END;
END;

PROCEDURE CheckWriteArgType(wexpr: ADRMEM; tk: INTEGER);
{ Reject non-writable aggregate arguments in the typechecker with a source
  location instead of failing later in codegen (CMP-26r). One-dimensional
  ARRAY OF CHAR (or CHAR subrange) stays accepted, matching cg_io.pas. }
VAR
  elem_tk: INTEGER;
  saved_line, saved_col: INTEGER32;
  saved_loc: ADRMEM;
  bad: BOOLEAN;
BEGIN
  IF (tk = TK_UNKNOWN) OR (tk = TK_VOID) THEN RETURN;
  bad := FALSE;
  IF tk = TK_ARRAY THEN
  BEGIN
    elem_tk := WriteArrayElemTk(wexpr);
    IF (elem_tk <> TK_CHAR) AND (elem_tk <> TK_UNKNOWN) THEN bad := TRUE;
  END
  ELSE IF (tk = TK_RECORD) OR (tk = TK_SET) OR (tk = TK_FILE) OR (tk = TK_VECTOR) THEN
    bad := TRUE;
  IF bad THEN
  BEGIN
    TcEnterLocation(wexpr, saved_line, saved_col, saved_loc);
    AddError('WRITE/WRITELN only supports scalar, string, or one-dimensional ARRAY OF CHAR arguments');
    TcLeaveLocation(saved_line, saved_col, saved_loc);
  END;
END;

PROCEDURE CheckAssignStmt(node: ADRMEM);
{ Kept out of CheckStmtBody so its recursive frame stays small (tests/corpus/depth.sh). }
VAR
  target_node, expr_node: ADRMEM;
  varname: Str255;
  target_tk, expr_tk, target_set_sem_base: INTEGER;
  target_scalar_sem_base, target_write_kind, fn_frame: INTEGER;
  target_super_str, expr_super_str: INTEGER;
  target_is_lstring: BOOLEAN;
BEGIN
  target_node := GetObj(node, 'target');
  expr_node := GetObj(node, 'expr');
  varname := GetStr(target_node, 'name');
  target_super_str := 0;
  expr_super_str := 0;
  fn_frame := ActiveFuncResultFrame(varname);
  IF (fn_frame <> 0) AND
     (cJSON_GetArraySize(GetObj(target_node, 'selectors')) = 0) THEN
  BEGIN
    { `F := expr` inside F's own body (or a nested routine inside F)
      assigns through the return-value slot, not any symbol-table entry.
      Matches case-insensitively (NEW-44) and respects inner shadowing. }
    target_tk := func_frames[fn_frame].ret_tk;
    target_set_sem_base := func_frames[fn_frame].set_sem_base;
    target_scalar_sem_base := func_frames[fn_frame].scalar_sem_base;
    target_is_lstring := (target_tk = TK_STRING) AND (func_frames[fn_frame].aux2 = 1);
    target_write_kind := WRITABLE_OK;
  END
  ELSE BEGIN
    target_tk := CheckDesignator(target_node);
    target_set_sem_base := last_designator_set_sem_base;
    target_scalar_sem_base := last_designator_scalar_sem_base;
    target_is_lstring := (target_tk = TK_STRING) AND (last_designator_aux2 = 1);
    target_write_kind := last_designator_write_kind;
    target_super_str := last_designator_super_str;
  END;
  { Snapshot before descending into the RHS: nested designators and calls
    overwrite their global result channels. }
  expr_tk := CheckExprForSetTarget(expr_node, target_tk, target_set_sem_base);
  IF (NodeType(expr_node) = 'Designator') OR (NodeType(expr_node) = 'PostfixExpr') THEN
    expr_super_str := last_designator_super_str;
  IF target_write_kind = WRITABLE_CONST THEN
    AddError2('Cannot assign to a constant: ', varname)
  ELSE IF target_write_kind = WRITABLE_CONST_PARAM THEN
    AddError2('Cannot assign to a CONST parameter: ', varname)
  ELSE IF target_write_kind = WRITABLE_NON_VAR THEN
  BEGIN
    IF varname = '' THEN
      AddError('Cannot assign to a non-variable')
    ELSE
      AddError2('Cannot assign to a non-variable: ', varname);
  END
  { A super-array STRING/LSTRING formal or pointer referent is assigned and
    read only by component (IBM manual 6-15, 6-16, 6-19); COPYLST, COPYSTR
    and the other string procedures or conformant formals take it whole. }
  ELSE IF SuperStringRefSym(target_node) <> 0 THEN
    AddError2('Cannot assign to a super-array STRING/LSTRING parameter as a whole: ', varname)
  ELSE IF SuperStringRefSym(expr_node) <> 0 THEN
    AddError2('Cannot assign a super-array STRING/LSTRING parameter as a whole to: ', varname)
  ELSE IF target_super_str <> 0 THEN
    AddError2('Cannot assign to a super-array STRING/LSTRING referent as a whole: ', varname)
  ELSE IF expr_super_str <> 0 THEN
    AddError2('Cannot assign a super-array STRING/LSTRING referent as a whole to: ', varname)
  { CHAR converts automatically to LSTRING (IBM manual 6-18, NEW-33). }
  ELSE IF NOT (CanAssign(target_tk, expr_tk) OR (target_is_lstring AND (expr_tk = TK_CHAR))) THEN
    AddError2('Cannot assign incompatible type without narrowing: ', varname)
  { Two enumerations are never assignment compatible. Both identities
    must be known (a deep selection's is read back from its type node). }
  ELSE IF (target_tk = TK_ENUM) AND (expr_tk = TK_ENUM) AND
          SemanticBasesConflict(target_scalar_sem_base, last_sem_scalar_base) THEN
    AddError2('Cannot assign a value of a different enumeration type: ', varname);
END;

PROCEDURE CheckStmtBody(node: ADRMEM);
VAR
  nt, varname: Str255;
  args_arr, warg, wexpr: ADRMEM;
  expr_tk, cond_tk, vi: INTEGER;
  si: INTEGER32;
  nargs, i, start_arg: INTEGER32;
  pname: Str255;
  with_targets, with_target: ADRMEM;
  n_with_targets, wi, fi, pushed: INTEGER32;
  with_tk, rec_id: INTEGER;
BEGIN
  stmt_depth := stmt_depth + 1;
  IF stmt_depth > MAX_STMT_DEPTH THEN
    AddError('statements nested too deeply (deeper than 256); try splitting the routine up')
  ELSE BEGIN
  IF node = NIL THEN
    nt := ''
  ELSE
    nt := NodeType(node);
  IF nt = 'AssignStmt' THEN
    CheckAssignStmt(node)
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    cond_tk := CheckExpr(GetObj(node, 'cond'));
    IF (cond_tk <> TK_BOOLEAN) AND (cond_tk <> TK_UNKNOWN) THEN
      AddError('IF condition must be BOOLEAN');
    CheckCompoundOrStmt(GetObj(node, 'then_branch'));
    CheckCompoundOrStmt(GetObj(node, 'else_branch'));
  END
  ELSE IF nt = 'WhileStmt' THEN
  BEGIN
    CheckUnrollHint(node, 'WHILE');
    cond_tk := CheckExpr(GetObj(node, 'cond'));
    IF (cond_tk <> TK_BOOLEAN) AND (cond_tk <> TK_UNKNOWN) THEN
      AddError('WHILE condition must be BOOLEAN');
    CheckCompoundOrStmt(GetObj(node, 'body'));
  END
  ELSE IF nt = 'RepeatStmt' THEN
  BEGIN
    CheckUnrollHint(node, 'REPEAT');
    cond_tk := CheckExpr(GetObj(node, 'cond'));
    IF (cond_tk <> TK_BOOLEAN) AND (cond_tk <> TK_UNKNOWN) THEN
      AddError('REPEAT UNTIL condition must be BOOLEAN');
    CheckStmtList(GetObj(node, 'body'));
  END
  ELSE IF nt = 'ForStmt' THEN
  BEGIN
    CheckUnrollHint(node, 'FOR');
    varname := GetStr(node, 'var');
    si := LookupSymbol(varname);
    IF si = 0 THEN
      AddError2('Undefined identifier: ', varname)
    ELSE BEGIN
      vi := symbols[si].tk;
      IF symbols[si].kind <> 'VAR' THEN
        AddError2('FOR control variable must be a variable: ', varname)
      ELSE IF symbols[si].is_ref_param THEN
        AddError2('FOR control variable cannot be a reference parameter: ',
                  varname);
      IF NOT IsOrdinal(vi) THEN
        AddError('FOR loop variable must be an ordinal type');
    END;
    IF si <> 0 THEN
    BEGIN
      cond_tk := CheckExprForTarget(GetObj(node, 'start'), vi);
      IF NOT CanAssign(vi, cond_tk) THEN
        AddError2('FOR initial bound is not assignment compatible: ', varname);
      cond_tk := CheckExprForTarget(GetObj(node, 'end'), vi);
      IF NOT CanAssign(vi, cond_tk) THEN
        AddError2('FOR final bound is not assignment compatible: ', varname);
    END
    ELSE BEGIN
      cond_tk := CheckExpr(GetObj(node, 'start'));
      cond_tk := CheckExpr(GetObj(node, 'end'));
    END;
    CheckCompoundOrStmt(GetObj(node, 'body'));
  END
  ELSE IF nt = 'CaseStmt' THEN
    CheckCaseStmt(node)
  ELSE IF nt = 'ProcCallStmt' THEN
  BEGIN
    pname := GetStr(node, 'name');
    args_arr := GetObj(node, 'args');
    nargs := cJSON_GetArraySize(args_arr);
    IF UserDeclarationShadows(pname) THEN
    BEGIN
      si := LookupSymbol(pname);
      IF (symbols[si].kind <> 'PROC') AND (symbols[si].kind <> 'FUNC') THEN
        AddError2('Not a procedure or function: ', pname)
      ELSE BEGIN
        { Same [VARARGS] arity relaxation as CheckFuncCall. }
        IF (nargs <> symbols[si].nparams)
           AND NOT (symbols[si].is_vararg AND (nargs > symbols[si].nparams)) THEN
          AddError('Argument count mismatch')
        ELSE
          FOR i := 0 TO nargs - 1 DO
          BEGIN
            warg := ShadowedWriteArg(cJSON_GetArrayItem(args_arr, i), pname);
            IF i < symbols[si].nparams THEN
              expr_tk := CheckExprForSetTarget(warg, symbols[si].param_tk[i + 1],
                symbols[si].param_set_sem_base[i + 1])
            ELSE
              expr_tk := CheckExpr(warg);
            IF i < symbols[si].nparams THEN
              CheckRoutineArg(warg, si, i + 1, expr_tk, pname);
          END;
      END;
    END
    ELSE IF (pname = 'WRITELN') OR (pname = 'WRITE') OR (pname = 'READLN') OR (pname = 'READ') THEN
    BEGIN
      { A leading file-variable argument (WRITE(F, ...) / READ(F, ...))
        selects the destination/source file instead of being a data
        argument -- detect and skip it, requiring it be a TEXT file (per
        the manual, a binary FILE isn't valid here). WRITE/WRITELN args are
        always WriteArg-wrapped (even the file selector); READ/READLN args
        never are. }
      start_arg := 0;
      IF nargs > 0 THEN
      BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) = 'WriteArg' THEN wexpr := GetObj(warg, 'expr') ELSE wexpr := warg;
        IF NodeType(wexpr) = 'Identifier' THEN
        BEGIN
          si := LookupSymbol(GetStr(wexpr, 'name'));
          { AND is eager in the native bootstrap: never index symbols[0]
            for an undefined name. }
          IF si <> 0 THEN
            IF symbols[si].tk = TK_FILE THEN
            BEGIN
              IF (symbols[si].aux <> TK_CHAR) OR (symbols[si].aux2 <> 1) THEN
                AddError('WRITE/WRITELN/READ/READLN file selector must be a TEXT file');
              start_arg := 1;
            END;
        END;
      END;
      FOR i := start_arg TO nargs - 1 DO
      BEGIN
        warg := cJSON_GetArrayItem(args_arr, i);
        IF NodeType(warg) = 'WriteArg' THEN
        BEGIN
          wexpr := GetObj(warg, 'expr');
          IF wexpr <> NIL THEN
          BEGIN
            cond_tk := CheckExpr(wexpr);
            CheckWriteArgType(wexpr, cond_tk);
          END;
        END
        ELSE IF (pname = 'READ') OR (pname = 'READLN') THEN
        BEGIN
          cond_tk := CheckExpr(warg);
          IF cond_tk <> TK_UNKNOWN THEN
          BEGIN
            IF ArgWriteKind(warg) = WRITABLE_CONST_PARAM THEN
              AddError('READ/READLN argument cannot be a CONST parameter')
            ELSE IF ArgWriteKind(warg) = WRITABLE_CONST THEN
              AddError('READ/READLN argument cannot be a constant');
          END;
        END;
      END;
    END
    ELSE IF (pname = 'RESET') OR (pname = 'REWRITE') OR (pname = 'GET') OR
            (pname = 'PUT') OR (pname = 'CLOSE') OR (pname = 'DISCARD') THEN
    BEGIN
      { All six file primitives take exactly one bare file-variable argument
        (of any structure, TEXT or binary -- unlike WRITE/READ/EOLN, none of
        these care whether the file is TEXT). }
      IF nargs <> 1 THEN
        AddError('Argument count mismatch')
      ELSE BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('file primitive argument must be a bare file variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddUndefinedIdentifier(warg)
          ELSE IF symbols[si].tk <> TK_FILE THEN
            AddError('file primitive argument must be a FILE variable');
        END;
      END;
    END
    ELSE IF pname = 'ASSIGN' THEN
    BEGIN
      IF nargs <> 2 THEN
        AddError('ASSIGN expects exactly two arguments')
      ELSE BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('ASSIGN argument 1 must be a bare file variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddUndefinedIdentifier(warg)
          ELSE IF symbols[si].tk <> TK_FILE THEN
            AddError('ASSIGN argument 1 must be a FILE variable');
        END;
        cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
        IF (cond_tk <> TK_STRING) AND (cond_tk <> TK_CHAR) AND (cond_tk <> TK_UNKNOWN) THEN
          AddError('ASSIGN argument 2 must be STRING, LSTRING, or CHAR');
      END;
    END
    ELSE IF pname = 'READSET' THEN
    BEGIN
      { READSET([file,] dest, set_of_char): manual-documented extended I/O
        builtin (djvu.txt), reads from `file` (INPUT if omitted) into `dest`
        until a delimiter char in `set_of_char` is seen. Mirrors the
        WRITE/READ file-selector detection above; dest is required to be
        assignable and LSTRING-shaped -- this coarse model conflates
        STRING/LSTRING into TK_STRING (see ResolveTypeExpr's NamedType
        case), so both are accepted here the same way ASSIGN's second
        argument already is. }
      IF (nargs <> 2) AND (nargs <> 3) THEN
        AddError('READSET expects 2 or 3 arguments')
      ELSE BEGIN
        start_arg := 0;
        IF nargs = 3 THEN
        BEGIN
          warg := cJSON_GetArrayItem(args_arr, 0);
          IF NodeType(warg) <> 'Identifier' THEN
            AddError('READSET file argument must be a bare file variable')
          ELSE BEGIN
            si := LookupSymbol(GetStr(warg, 'name'));
            IF si = 0 THEN
              AddUndefinedIdentifier(warg)
            ELSE IF (symbols[si].tk <> TK_FILE) OR (symbols[si].aux <> TK_CHAR) OR (symbols[si].aux2 <> 1) THEN
              AddError('READSET file argument must be a TEXT file');
          END;
          start_arg := 1;
        END;
        warg := cJSON_GetArrayItem(args_arr, start_arg);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('READSET destination must be a bare LSTRING variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddUndefinedIdentifier(warg)
          ELSE IF (symbols[si].kind <> 'VAR') OR symbols[si].is_const_param THEN
            AddError('READSET destination must be a writable LSTRING variable')
          ELSE IF symbols[si].tk <> TK_STRING THEN
            AddError('READSET destination must be STRING or LSTRING');
        END;
        warg := cJSON_GetArrayItem(args_arr, start_arg + 1);
        IF (NodeType(warg) = 'SetConstructor') AND
           (GetObjOrNil(warg, 'type_name') = NIL) AND
           (NOT active_features.readset_set_literal) THEN
          AddError('Character Set Expected: READSET set argument must be a declared SET OF CHAR value');
        cond_tk := CheckExprForSetTarget(warg, TK_SET, TK_CHAR);
        IF cond_tk <> TK_SET THEN
          AddError('READSET set argument must be a SET OF CHAR value');
      END;
    END
    ELSE IF (pname = 'NEW') OR (pname = 'DISPOSE') THEN
      CheckNewDispose(args_arr, pname)
    ELSE IF pname = 'COPYLST' THEN
      CheckCopylst(args_arr)
    ELSE IF pname = 'COPYSTR' THEN
      CheckCopystr(args_arr)
    ELSE IF pname = 'DELETE' THEN
      CheckDelete(args_arr)
    ELSE IF pname = 'INSERT' THEN
      CheckInsert(args_arr)
    ELSE IF pname = 'CONCAT' THEN
    BEGIN
      { CONCAT(VAR d: LSTRING-or-STRING-or-Str255; CONST s: STRING-or-
        LSTRING-or-literal): the language's own built-in string-append
        procedure (distinct from codegen.pas's own target-language CONCAT
        support, which reads this same AST node shape but for a *user*
        program's CONCAT call) -- not otherwise special-cased anywhere in
        this file, so every native .pas source that calls it as a bare
        statement (codegen.pas does, heavily, to build up format strings)
        previously hit "Undefined procedure" here. Checked leniently, same
        as WRITE/WRITELN above: this file's coarse tk model has no
        separate Str255/STRING/LSTRING distinction worth enforcing here. }
      IF nargs <> 2 THEN
        AddError('CONCAT requires exactly two arguments')
      ELSE
        FOR i := 0 TO nargs - 1 DO
        BEGIN
          warg := cJSON_GetArrayItem(args_arr, i);
          cond_tk := CheckExpr(warg);
          IF (i = 0) AND (cond_tk <> TK_UNKNOWN) AND
             ((ArgWriteKind(warg) = WRITABLE_CONST_PARAM) OR
              (ArgWriteKind(warg) = WRITABLE_CONST)) THEN
            AddError('CONCAT destination must be a writable string variable');
        END;
    END
    ELSE IF IsHostDeviceIntrinsic(pname) THEN
      CheckHostDeviceIntrinsic(node, pname)
    ELSE IF IsDeviceSyncIntrinsic(pname) THEN
      CheckDeviceSyncIntrinsic(node, pname)
    ELSE IF pname = 'VSTORE' THEN
    BEGIN
      { VSTORE(arr, i, v): statement-form store of vector v's lanes into
        arr[i .. i+n-1]. No builtin-procedure table exists -- this is a
        branch in the same hardcoded chain (cf. NEW/CONCAT above). Element
        match and constant-index bounds are codegen's job. }
      IF nargs <> 3 THEN
        AddError('VSTORE requires exactly three arguments (an array, an index and a VECTOR value)')
      ELSE
      BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        cond_tk := CheckExpr(warg);
        IF (cond_tk <> TK_ARRAY) AND (cond_tk <> TK_UNKNOWN) THEN
          AddError('VSTORE first argument must be an array')
        ELSE IF (cond_tk = TK_ARRAY) AND
                ((ArgWriteKind(warg) = WRITABLE_CONST_PARAM) OR
                 (ArgWriteKind(warg) = WRITABLE_CONST)) THEN
          AddError('VSTORE destination must be a writable array');
        cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
        IF NOT IsInteger(cond_tk) AND (cond_tk <> TK_UNKNOWN) THEN
          AddError('VSTORE index must be an integer type');
        cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 2));
        IF (cond_tk <> TK_VECTOR) AND (cond_tk <> TK_UNKNOWN) THEN
          AddError('VSTORE third argument must be a VECTOR value');
      END;
    END
    ELSE BEGIN
      si := LookupSymbol(pname);
      IF si = 0 THEN
      BEGIN
        AddError2('Undefined procedure: ', pname);
        FOR i := 0 TO nargs - 1 DO
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
      END
      ELSE IF (symbols[si].kind <> 'PROC') AND (symbols[si].kind <> 'FUNC') THEN
        AddError2('Not a procedure or function: ', pname)
      ELSE BEGIN
        { Same [VARARGS] arity relaxation as CheckFuncCall above. }
        IF (nargs <> symbols[si].nparams)
           AND NOT (symbols[si].is_vararg AND (nargs > symbols[si].nparams)) THEN
          AddError('Argument count mismatch')
        ELSE
          FOR i := 0 TO nargs - 1 DO
          BEGIN
            IF i < symbols[si].nparams THEN
              expr_tk := CheckExprForSetTarget(cJSON_GetArrayItem(args_arr, i),
                symbols[si].param_tk[i + 1], symbols[si].param_set_sem_base[i + 1])
            ELSE
              expr_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
            IF i < symbols[si].nparams THEN
              CheckRoutineArg(cJSON_GetArrayItem(args_arr, i), si, i + 1, expr_tk, pname);
          END;
      END;
    END;
  END
  ELSE IF nt = 'CompoundStmt' THEN
    CheckCompoundOrStmt(node)
  ELSE IF nt = 'LabelStmt' THEN
    CheckStmt(GetObj(node, 'stmt'))
  ELSE IF nt = 'GotoStmt' THEN
    CheckGotoStmt(node)
  ELSE IF nt = 'WithStmt' THEN
  BEGIN
    { WITH t1, t2, ... DO body -- equivalent to WITH t1 DO WITH t2 DO ...
      DO body (djvu.txt:10194-10198): push one scope per target left to
      right, each target's fields becoming bare identifiers visible in the
      inner scope, so a later target's field of the same name shadows an
      earlier one -- LookupSymbol's backward scan gives this for free. Only
      a RECORD-typed target is legal; a bare pointer-to-record is rejected
      (must be explicitly DEREF'd first), matching the reference and the
      manual. }
    with_targets := GetObj(node, 'targets');
    n_with_targets := cJSON_GetArraySize(with_targets);
    pushed := 0;
    FOR wi := 0 TO n_with_targets - 1 DO
    BEGIN
      with_target := cJSON_GetArrayItem(with_targets, wi);
      with_tk := CheckDesignator(with_target);
      IF with_tk = TK_RECORD THEN
      BEGIN
        rec_id := last_designator_aux;
        PushScope;
        pushed := pushed + 1;
        FOR fi := 1 TO nfields DO
          IF fields[fi].record_id = rec_id THEN
          BEGIN
            si := DefineSymbol(fields[fi].fname, 'VAR', fields[fi].ftk, fields[fi].faux, fields[fi].faux2, fields[fi].faux3, fields[fi].fidx_tk);
            symbols[si].type_node := fields[fi].type_node;
            symbols[si].type_bound := last_designator_type_bound;
            symbols[si].set_sem_base := fields[fi].set_sem_base;
            symbols[si].scalar_sem_base := fields[fi].scalar_sem_base;
            symbols[si].is_const_param := last_designator_write_kind <> WRITABLE_OK;
          END;
      END
      ELSE IF with_tk <> TK_UNKNOWN THEN
        AddError('WITH target must be a record');
    END;
    CheckCompoundOrStmt(GetObj(node, 'body'));
    FOR wi := 1 TO pushed DO
      PopScope;
  END;
  END;
  stmt_depth := stmt_depth - 1;
END;

PROCEDURE CheckStmt(node: ADRMEM);
{ CheckStmtBody with the error position at this statement while it is
  checked. }
VAR
  saved_line, saved_col: INTEGER32;
  saved_loc: ADRMEM;
BEGIN
  TcEnterLocation(node, saved_line, saved_col, saved_loc);
  CheckStmtBody(node);
  TcLeaveLocation(saved_line, saved_col, saved_loc);
END;

BEGIN
END.
