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

PROCEDURE CheckStmt(node: ADRMEM); FORWARD;

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
              expr_tk := CheckExprForTarget(cJSON_GetArrayItem(args_arr, start_arg + i),
                                            symbols[si].param_tk[i + 1]);
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

PROCEDURE CheckCaseLabel(label_node: ADRMEM; sel_tk: INTEGER);
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
    { Neither codegen nor the Python reference lowers a label range; say so
      here, where the whole CASE is still in view and the rest of the
      compiland's errors are collected, rather than at codegen's abort. }
    AddError('a CASE label range (lo..hi) is not yet supported');
    label_tk := CheckExprForTarget(GetObj(label_node, 'low'), sel_tk);
    label_tk := CheckExprForTarget(GetObj(label_node, 'high'), sel_tk);
  END
  ELSE
  BEGIN
    label_tk := CheckExprForTarget(label_node, sel_tk);
    IF NOT CanAssign(sel_tk, label_tk) THEN
      AddError('CASE label type is incompatible with the selector type');
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
  sel_tk: INTEGER;
  n, i, nc, ci: INTEGER32;
BEGIN
  sel_tk := CheckExpr(GetObj(node, 'expr'));
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
      CheckCaseLabel(cJSON_GetArrayItem(constants_arr, ci), sel_tk);
    CheckCompoundOrStmt(GetObjOrNil(el, 'stmt'));
  END;
  otherwise_stmt := GetObjOrNil(node, 'otherwise');
  IF otherwise_stmt <> NIL THEN
    CheckCompoundOrStmt(otherwise_stmt);
END;

PROCEDURE CheckStmt(node: ADRMEM);
VAR
  nt, varname: Str255;
  target_node, expr_node, cond_node, args_arr, warg, wexpr: ADRMEM;
  target_tk, expr_tk, cond_tk, vi: INTEGER;
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
  BEGIN
    target_node := GetObj(node, 'target');
    expr_node := GetObj(node, 'expr');
    varname := GetStr(target_node, 'name');
    IF (cur_func_name <> '') AND (varname = cur_func_name) AND
       (cJSON_GetArraySize(GetObj(target_node, 'selectors')) = 0) THEN
    BEGIN
      { `F := expr` inside F's own body assigns through the return-value
        slot, not any symbol-table entry (see cur_func_name's doc comment
        -- this must NOT fall through to CheckDesignator, which would
        either miss it (no such VAR symbol) or, worse, collide with a
        same-named callable symbol). }
      target_tk := cur_func_ret_tk;
    END
    ELSE
      target_tk := CheckDesignator(target_node);
    expr_tk := CheckExprForTarget(expr_node, target_tk);
    IF NOT CanAssign(target_tk, expr_tk) THEN
      AddError2('Cannot assign incompatible type without narrowing: ', varname);
  END
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
      AddError('Undefined identifier')
    ELSE BEGIN
      vi := symbols[si].tk;
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
    IF (pname = 'WRITELN') OR (pname = 'WRITE') OR (pname = 'READLN') OR (pname = 'READ') THEN
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
          IF (si <> 0) AND (symbols[si].tk = TK_FILE) THEN
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
          IF wexpr <> NIL THEN cond_tk := CheckExpr(wexpr);
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
            AddError('Undefined identifier')
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
            AddError('Undefined identifier')
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
              AddError('Undefined identifier')
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
            AddError('Undefined identifier')
          ELSE IF symbols[si].tk <> TK_STRING THEN
            AddError('READSET destination must be STRING or LSTRING');
        END;
        warg := cJSON_GetArrayItem(args_arr, start_arg + 1);
        IF (NodeType(warg) = 'SetConstructor') AND
           (GetObjOrNil(warg, 'type_name') = NIL) AND
           (NOT active_features.readset_set_literal) THEN
          AddError('Character Set Expected: READSET set argument must be a declared SET OF CHAR value');
        cond_tk := CheckExpr(warg);
        IF cond_tk <> TK_SET THEN
          AddError('READSET set argument must be a SET OF CHAR value');
      END;
    END
    ELSE IF (pname = 'NEW') OR (pname = 'DISPOSE') THEN
    BEGIN
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
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('NEW/DISPOSE argument must be a bare pointer variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddError('Undefined identifier')
          ELSE IF symbols[si].tk <> TK_POINTER THEN
            AddError('NEW/DISPOSE argument must be a POINTER variable');
        END;
        IF nargs = 2 THEN
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
      END;
    END
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
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
    END
    ELSE IF IsHostDeviceIntrinsic(pname) THEN
      CheckHostDeviceIntrinsic(node, pname)
    ELSE IF IsDeviceSyncIntrinsic(pname) AND (LookupSymbol(pname) = 0) THEN
      { A user declaration of this name takes precedence over the builtin
        (IBM Pascal, Aug 1981, p.3-7: predeclared identifiers "can be
        re-defined by the programmer" -- see
        tests/fixtures/typecheck/should_pass/builtin_type_shadowing.pas).
        Only dispatch to the intrinsic when no such declaration is visible;
        otherwise fall through to the ordinary call below. }
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
        cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
        IF (cond_tk <> TK_ARRAY) AND (cond_tk <> TK_UNKNOWN) THEN
          AddError('VSTORE first argument must be an array');
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
        AddError('Undefined procedure');
        FOR i := 0 TO nargs - 1 DO
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
      END
      ELSE BEGIN
        { Same [VARARGS] arity relaxation as CheckFuncCall above. }
        IF (nargs <> symbols[si].nparams)
           AND NOT (symbols[si].is_vararg AND (nargs > symbols[si].nparams)) THEN
          AddError('Argument count mismatch')
        ELSE
          FOR i := 0 TO nargs - 1 DO
          BEGIN
            IF i < symbols[si].nparams THEN
              expr_tk := CheckExprForTarget(cJSON_GetArrayItem(args_arr, i),
                                            symbols[si].param_tk[i + 1])
            ELSE
              expr_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
            IF i < symbols[si].nparams THEN
              IF NOT CanAssign(symbols[si].param_tk[i + 1], expr_tk) THEN
                AddError2('Argument type mismatch or implicit narrowing in call to ', pname);
          END;
      END;
    END;
  END
  ELSE IF nt = 'CompoundStmt' THEN
    CheckCompoundOrStmt(node)
  ELSE IF nt = 'LabelStmt' THEN
    { <label>: <stmt> -- the label declaration/target itself isn't checked
      (matching the Python reference, which builds no label table and
      leaves GOTO unchecked; codegen.pas is the enforcement point for
      "GOTO to undefined label", same as the reference), but the *inner*
      statement must still be walked. Omitting this case previously meant
      any statement reached only via a label silently skipped type
      checking -- the same class of bug as the historical CompoundStmt
      dispatch gap (see this file's header comment / §1.7). }
    CheckStmt(GetObj(node, 'stmt'))
  ELSE IF nt = 'GotoStmt' THEN
    { No-op: see the LabelStmt case's comment above. }
    BEGIN END
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
            si := DefineSymbol(fields[fi].fname, 'VAR', fields[fi].ftk, fields[fi].faux, fields[fi].faux2, 0);
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

BEGIN
END.
