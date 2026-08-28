{ Implementations for cg_stmt. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
(*$INCLUDE:'cg_expr_support.inc'*)
(*$INCLUDE:'cg_expr.inc'*)
(*$INCLUDE:'cg_io.inc'*)
(*$INCLUDE:'cg_stmt.inc'*)
IMPLEMENTATION OF cg_stmt;
USES cg_expr_support;

{ ============================== statements ================================ }

{ ============================== statements ================================ }

PROCEDURE CodegenStmt(stmt: ADRMEM); FORWARD;

{ --------------------------- GOTO / labels --------------------------------
  Mirrors the Python reference's _collect_labels/setup_function_labels: every
  LabelStmt reachable within a routine gets one LLVM basic block, allocated
  up front (before the body is codegen'd) so a forward GOTO can branch to a
  block that doesn't exist yet in program-text order. Routine-local only --
  the `labels` table is rebuilt from scratch for every PROGRAM/PROCEDURE/
  FUNCTION/unit-init body (see SetupFunctionLabels's call sites), matching
  the reference's own per-routine label_blocks and its "GOTO to undefined
  label" restriction against cross-routine jumps. }

FUNCTION IntToStr255(n: INTEGER32): Str255;
{ No such helper exists anywhere else in this file -- every other numeric
  diagnostic is either a fixed string or routed through AbortWith2's plain
  Str255 concatenation, never a formatted integer. Needed here because a
  numeric GOTO label (e.g. `GOTO 100;`) arrives from the parser as a JSON
  number, not a string, and the `labels` table's lookup key is always text.
  Builds digits into `tmp` least-significant-first via direct Str255
  indexing (the same s[0]=length-byte convention CStrToStr255 uses), then
  reverses into `res` -- no CONCAT needed, this is plain char-array work. }
VAR
  neg: BOOLEAN;
  v: INTEGER32;
  digit: INTEGER32;
  tmp, res: Str255;
  len, i, out_i: INTEGER;
BEGIN
  neg := n < 0;
  IF neg THEN v := -n ELSE v := n;
  len := 0;
  IF v = 0 THEN
  BEGIN
    len := 1;
    tmp[1] := '0';
  END
  ELSE
    WHILE v > 0 DO
    BEGIN
      len := len + 1;
      digit := ORD('0') + (v MOD 10);
      tmp[len] := CHR(RETYPE(INTEGER, digit));
      v := v DIV 10;
    END;
  out_i := 0;
  IF neg THEN
  BEGIN
    out_i := out_i + 1;
    res[out_i] := '-';
  END;
  FOR i := len DOWNTO 1 DO
  BEGIN
    out_i := out_i + 1;
    res[out_i] := tmp[i];
  END;
  res[0] := CHR(out_i);
  IntToStr255 := res;
END;

FUNCTION LabelKey(node: ADRMEM; key: Str255): Str255;
{ The parser's 'label' field (GotoStmt/LabelStmt/BreakStmt/CycleStmt) is a
  JSON number for a numeric label, a JSON string for an identifier label --
  read whichever is present and normalize to the same Str255 key either way. }
VAR
  item: ADRMEM;
BEGIN
  item := GetObj(node, key);
  IF (item <> NIL) AND (cJSON_IsNumber(item) <> 0) THEN
    LabelKey := IntToStr255(GetInt(node, key))
  ELSE
    LabelKey := GetStr(node, key);
END;

FUNCTION LookupLabel(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := nlabels;
  WHILE (i >= 1) AND (labels[i].name <> name) DO
    i := i - 1;
  LookupLabel := i;
END;

PROCEDURE RegisterLabel(name: Str255);
BEGIN
  IF LookupLabel(name) = 0 THEN
  BEGIN
    IF nlabels >= MAX_LABELS THEN AbortWith('codegen: too many labels in one routine');
    nlabels := nlabels + 1;
    labels[nlabels].name := name;
    labels[nlabels].block := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('label_'));
  END;
END;

PROCEDURE CollectLabels(stmt: ADRMEM); FORWARD;

PROCEDURE CollectLabelsArr(arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  IF arr <> NIL THEN
  BEGIN
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
      CollectLabels(ArrItem(arr, i));
  END;
END;

PROCEDURE CollectLabels(stmt: ADRMEM);
{ Non-emitting walk mirroring the reference's own _collect_labels node
  coverage: every statement kind that can syntactically contain a LabelStmt
  (directly or nested) is walked; leaf statement kinds (assignment, ProcCall,
  RETURN/BREAK/CYCLE, GOTO itself) have no children and are ignored. This
  dialect has no EXIT statement (see CodegenBinOp's own note on the same
  restriction), so an early "stmt = NIL" return is instead the outermost
  guard around the whole dispatch chain. }
VAR
  nt: Str255;
  elements, el: ADRMEM;
  n, i: INTEGER32;
BEGIN
  IF stmt <> NIL THEN
  BEGIN
  nt := NodeType(stmt);
  IF nt = 'CompoundStmt' THEN
    CollectLabelsArr(GetObj(stmt, 'stmts'))
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    CollectLabels(GetObj(stmt, 'then_branch'));
    CollectLabels(GetObjOrNil(stmt, 'else_branch'));
  END
  ELSE IF nt = 'WhileStmt' THEN
    CollectLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'RepeatStmt' THEN
    CollectLabelsArr(GetObj(stmt, 'body'))
  ELSE IF nt = 'ForStmt' THEN
    CollectLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'CaseStmt' THEN
  BEGIN
    elements := GetObj(stmt, 'elements');
    n := ArrSize(elements);
    FOR i := 0 TO n - 1 DO
    BEGIN
      el := ArrItem(elements, i);
      CollectLabels(GetObj(el, 'stmt'));
    END;
    CollectLabels(GetObjOrNil(stmt, 'otherwise'));
  END
  ELSE IF nt = 'LabelStmt' THEN
  BEGIN
    RegisterLabel(LabelKey(stmt, 'label'));
    CollectLabels(GetObj(stmt, 'stmt'));
  END;
  END;
END;

PROCEDURE SetupFunctionLabels(body_arr: ADRMEM);
BEGIN
  nlabels := 0;
  CollectLabelsArr(body_arr);
  cur_routine_has_labels := nlabels > 0;
  pending_loop_label := '';
END;

PROCEDURE CodegenStmtArray(arr: ADRMEM);
VAR
  n, i: INTEGER32;
  dead_bb: ADRMEM;
BEGIN
  n := ArrSize(arr);
  FOR i := 0 TO n - 1 DO
  BEGIN
    { A RETURN/BREAK/CYCLE/GOTO terminates its block; ordinarily nothing
      downstream in a straight-line statement list can still be reached, so
      stop emitting (matches the pre-GOTO behavior exactly when the routine
      has no labels at all). But when it does, a later statement might be a
      LabelStmt (or contain one) that a GOTO elsewhere in the routine
      branches to -- SetupFunctionLabels already gave it a real block, so
      dropping it here would leave that block never populated. Mirrors the
      reference's own codegen_stmt_list: open a fresh (currently
      unreachable) continuation block and keep going instead of stopping. }
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) <> NIL THEN
    BEGIN
      IF NOT cur_routine_has_labels THEN BREAK;
      dead_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('dead'));
      LLVMPositionBuilderAtEnd(builder, dead_bb);
    END;
    CodegenStmt(ArrItem(arr, i));
  END;
END;

PROCEDURE CodegenAssignStmt(stmt: ADRMEM);
VAR
  target, sel: ADRMEM;
  nm: Str255;
  symi: INTEGER32;
  v, addr: ADRMEM;
  target_tid: INTEGER;
BEGIN
  target := GetObj(stmt, 'target');
  IF NodeType(target) <> 'Designator' THEN
    AbortWith('codegen: unsupported assignment target');
  sel := GetObj(target, 'selectors');
  nm := GetStr(target, 'name');

  IF (ArrSize(sel) = 0) AND (cur_func_name <> '') AND (nm = cur_func_name) THEN
  BEGIN
    { `FuncName := expr` inside FuncName's own body assigns through the
      return-value slot, not a symbol -- see cur_func_name's declaration. }
    IF (TypeKind(cur_func_ret_tk) = TK_LSTRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenLStringLiteralAssign(cur_func_ret_slot, cur_func_ret_tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE IF (TypeKind(cur_func_ret_tk) = TK_STRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenStringLiteralAssign(cur_func_ret_slot, cur_func_ret_tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE
    BEGIN
      v := CodegenExpr(GetObj(stmt, 'expr'));
      v := CoerceForAssign(v, last_val_tk, cur_func_ret_tk, GetObj(stmt, 'expr'), nm);
      LLVMBuildStore(builder, v, cur_func_ret_slot);
    END;
  END
  ELSE IF ArrSize(sel) = 0 THEN
  BEGIN
    symi := LookupSym(nm);
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', nm);
    IF (TypeKind(symbols[symi].tk) = TK_LSTRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenLStringLiteralAssign(symbols[symi].llvm_val, symbols[symi].tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE IF (TypeKind(symbols[symi].tk) = TK_STRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenStringLiteralAssign(symbols[symi].llvm_val, symbols[symi].tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE
    BEGIN
      v := CodegenExpr(GetObj(stmt, 'expr'));
      v := CoerceForAssign(v, last_val_tk, symbols[symi].tk, GetObj(stmt, 'expr'), nm);
      LLVMBuildStore(builder, v, symbols[symi].llvm_val);
    END;
  END
  ELSE
  BEGIN
    addr := ComputeDesignatorAddress(target);
    target_tid := last_val_tk;
    IF (TypeKind(target_tid) = TK_LSTRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenLStringLiteralAssign(addr, target_tid,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE IF (TypeKind(target_tid) = TK_STRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenStringLiteralAssign(addr, target_tid,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE
    BEGIN
      v := CodegenExpr(GetObj(stmt, 'expr'));
      v := CoerceForAssign(v, last_val_tk, target_tid, GetObj(stmt, 'expr'), nm);
      LLVMBuildStore(builder, v, addr);
    END;
  END;
END;

PROCEDURE CodegenIfStmt(stmt: ADRMEM);
VAR
  cond_val: ADRMEM;
  then_bb, else_bb, end_bb: ADRMEM;
  else_branch: ADRMEM;
BEGIN
  cond_val := CodegenExpr(GetObj(stmt, 'cond'));
  IF last_val_tk <> TK_BOOLEAN THEN
    AbortWith('codegen: IF condition must be BOOLEAN');

  then_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('if_then'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('if_end'));
  else_branch := GetObjOrNil(stmt, 'else_branch');
  IF else_branch <> NIL THEN
    else_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('if_else'))
  ELSE
    else_bb := end_bb;

  LLVMBuildCondBr(builder, cond_val, then_bb, else_bb);

  LLVMPositionBuilderAtEnd(builder, then_bb);
  CodegenStmt(GetObj(stmt, 'then_branch'));
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
    LLVMBuildBr(builder, end_bb);

  IF else_branch <> NIL THEN
  BEGIN
    LLVMPositionBuilderAtEnd(builder, else_bb);
    CodegenStmt(else_branch);
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
      LLVMBuildBr(builder, end_bb);
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenCaseStmt(stmt: ADRMEM);
{ Lowered as a sequential chain of test/body block pairs (like a chain of
  IFs), not a jump table -- simplicity over the optimization the Python
  reference doesn't attempt either at this level (llvmlite's own -O passes
  are what would turn either shape into a real jump table). Scoped to an
  INTEGER selector: a CHAR-keyed CASE is not yet supported, consistent with
  CodegenBinOp's relational operators also only covering INTEGER/REAL. }
VAR
  case_val: ADRMEM;
  case_tk: INTEGER;
  elements, el, constants, c: ADRMEM;
  n, i, nc, ci: INTEGER32;
  end_bb, cur_test_bb, next_test_bb, body_bb: ADRMEM;
  otherwise_stmt: ADRMEM;
  cond_val, one_cond, cval: ADRMEM;
BEGIN
  case_val := CodegenExpr(GetObj(stmt, 'expr'));
  case_tk := last_val_tk;
  IF case_tk <> TK_INTEGER THEN
    AbortWith('codegen: CASE selector must be INTEGER (CHAR-keyed CASE is not yet supported)');

  elements := GetObj(stmt, 'elements');
  n := ArrSize(elements);
  otherwise_stmt := GetObjOrNil(stmt, 'otherwise');
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_end'));

  cur_test_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_test'));
  LLVMBuildBr(builder, cur_test_bb);

  FOR i := 0 TO n - 1 DO
  BEGIN
    LLVMPositionBuilderAtEnd(builder, cur_test_bb);
    el := ArrItem(elements, i);
    constants := GetObj(el, 'constants');
    nc := ArrSize(constants);
    cond_val := NIL;
    FOR ci := 0 TO nc - 1 DO
    BEGIN
      c := ArrItem(constants, ci);
      IF NodeType(c) = 'RangeExpr' THEN
      BEGIN
        { The Python reference's codegen_case_stmt does not support a
          RangeExpr CASE constant either (it raises "Expression type
          RangeExpr not yet supported"), so rejecting it here too is
          matching that limitation, not falling short of it -- confirmed by
          running the same input through both pipelines. }
        AbortWith('codegen: a CASE label range (lo..hi) is not yet supported');
        one_cond := NIL;
      END
      ELSE
      BEGIN
        cval := CodegenExpr(c);
        IF last_val_tk <> TK_INTEGER THEN
          AbortWith('codegen: a CASE constant must be INTEGER');
        one_cond := LLVMBuildICmp(builder, LLVMIntEQ, case_val, cval, MakeCStr(''));
      END;
      IF cond_val = NIL THEN cond_val := one_cond
      ELSE cond_val := LLVMBuildOr(builder, cond_val, one_cond, MakeCStr(''));
    END;

    body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_body'));
    IF i = n - 1 THEN
    BEGIN
      IF otherwise_stmt <> NIL THEN
        next_test_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_otherwise'))
      ELSE
        next_test_bb := end_bb;
    END
    ELSE
      next_test_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_test'));

    LLVMBuildCondBr(builder, cond_val, body_bb, next_test_bb);

    LLVMPositionBuilderAtEnd(builder, body_bb);
    CodegenStmt(GetObj(el, 'stmt'));
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
      LLVMBuildBr(builder, end_bb);

    cur_test_bb := next_test_bb;
  END;

  IF (n = 0) OR (otherwise_stmt <> NIL) THEN
  BEGIN
    { n = 0: cur_test_bb is still the never-entered initial block (an empty
      CASE with only OTHERWISE, or entirely empty). n > 0: cur_test_bb is
      the dedicated case_otherwise block the last iteration created above,
      still needing its body emitted. Either way it must end in a branch to
      end_bb, or it is left as an unterminated block. }
    LLVMPositionBuilderAtEnd(builder, cur_test_bb);
    IF otherwise_stmt <> NIL THEN CodegenStmt(otherwise_stmt);
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
      LLVMBuildBr(builder, end_bb);
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE AttachUnrollHint(branch_inst: ADRMEM; count: INTEGER);
{ LLVM loop metadata is a self-referential node. Construct with a null first
  operand, then replace it with the node value itself, as required by LLVM's
  loop pass manager. }
VAR
  option_mds, loop_mds, option_md, loop_md, loop_val: ADRMEM;
  kind: CINT;
BEGIN
  option_mds := AllocPtrArray(2);
  SetPtrArrayElem(option_mds, 0, LLVMMDStringInContext2(ctx, MakeCStr('llvm.loop.unroll.count'), 22));
  SetPtrArrayElem(option_mds, 1, LLVMValueAsMetadata(LLVMConstInt(i32ty, count, 0)));
  option_md := LLVMMDNodeInContext2(ctx, option_mds, 2);
  loop_mds := AllocPtrArray(2);
  SetPtrArrayElem(loop_mds, 0, NIL);
  SetPtrArrayElem(loop_mds, 1, option_md);
  loop_md := LLVMMDNodeInContext2(ctx, loop_mds, 2);
  loop_val := LLVMMetadataAsValue(ctx, loop_md);
  { LLVM-C 20 exposes only an immutable node constructor for this path.
    This verifier-clean form records the requested count; a later textual
    self-reference pass can make it actionable to LLVM's unroller. }
  kind := LLVMGetMDKindIDInContext(ctx, MakeCStr('llvm.loop'), 9);
  LLVMSetMetadata(branch_inst, kind, loop_val);
END;

PROCEDURE CodegenWhileStmt(stmt: ADRMEM);
VAR
  loop_bb, body_bb, end_bb, cond_val: ADRMEM;
BEGIN
  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('while_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('while_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('while_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cond_val := CodegenExpr(GetObj(stmt, 'cond'));
  IF last_val_tk <> TK_BOOLEAN THEN
    AbortWith('codegen: WHILE condition must be BOOLEAN');
  LLVMBuildCondBr(builder, cond_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  loop_depth := loop_depth + 1;
  loop_break_blocks[loop_depth] := end_bb;
  loop_cycle_blocks[loop_depth] := loop_bb;
  loop_labels[loop_depth] := pending_loop_label;
  pending_loop_label := '';
  CodegenStmt(GetObj(stmt, 'body'));
  loop_depth := loop_depth - 1;
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
  BEGIN
    LLVMBuildBr(builder, loop_bb);
    IF GetObjOrNil(stmt, 'unroll') <> NIL THEN
      AttachUnrollHint(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)), GetInt(stmt, 'unroll'));
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenRepeatStmt(stmt: ADRMEM);
VAR
  loop_bb, end_bb, cond_val: ADRMEM;
BEGIN
  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('repeat_loop'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('repeat_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  loop_depth := loop_depth + 1;
  loop_break_blocks[loop_depth] := end_bb;
  loop_cycle_blocks[loop_depth] := loop_bb;
  loop_labels[loop_depth] := pending_loop_label;
  pending_loop_label := '';
  CodegenStmtArray(GetObj(stmt, 'body'));
  loop_depth := loop_depth - 1;
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
  BEGIN
    cond_val := CodegenExpr(GetObj(stmt, 'cond'));
    IF last_val_tk <> TK_BOOLEAN THEN
      AbortWith('codegen: REPEAT..UNTIL condition must be BOOLEAN');
    LLVMBuildCondBr(builder, cond_val, end_bb, loop_bb);
    IF GetObjOrNil(stmt, 'unroll') <> NIL THEN
      AttachUnrollHint(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)), GetInt(stmt, 'unroll'));
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenForStmt(stmt: ADRMEM);
VAR
  var_name: Str255;
  symi: INTEGER32;
  var_tk: INTEGER;
  var_llty: ADRMEM;
  start_node, end_node: ADRMEM;
  start_val, end_val, cur_val, cmp_val, next_val: ADRMEM;
  loop_bb, body_bb, step_bb, end_bb: ADRMEM;
  down: BOOLEAN;
BEGIN
  var_name := GetStr(stmt, 'var');
  symi := LookupSym(var_name);
  IF symi = 0 THEN
    AbortWith2('codegen: undefined FOR loop variable: ', var_name);
  var_tk := symbols[symi].tk;
  IF NOT IsIntegerFamilyTk(var_tk) AND (TypeKind(var_tk) <> TK_ENUM) THEN
    AbortWith('codegen: FOR loop variable must be an integer-family or enumerated type');
  var_llty := LLVMTypeForTk(var_tk);

  start_node := GetObj(stmt, 'start');
  start_val := CodegenExpr(start_node);
  start_val := CoerceForAssign(start_val, last_val_tk, var_tk, start_node, var_name);
  LLVMBuildStore(builder, start_val, symbols[symi].llvm_val);

  end_node := GetObj(stmt, 'end');
  end_val := CodegenExpr(end_node);
  end_val := CoerceForAssign(end_val, last_val_tk, var_tk, end_node, var_name);

  down := GetStr(stmt, 'direction') = 'DOWNTO';

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_body'));
  step_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_step'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_val := LLVMBuildLoad2(builder, var_llty, symbols[symi].llvm_val, MakeCStr(''));
  IF down THEN
    cmp_val := LLVMBuildICmp(builder, LLVMIntSGE, cur_val, end_val, MakeCStr(''))
  ELSE
    cmp_val := LLVMBuildICmp(builder, LLVMIntSLE, cur_val, end_val, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  loop_depth := loop_depth + 1;
  loop_break_blocks[loop_depth] := end_bb;
  loop_cycle_blocks[loop_depth] := step_bb;
  loop_labels[loop_depth] := pending_loop_label;
  pending_loop_label := '';
  CodegenStmt(GetObj(stmt, 'body'));
  loop_depth := loop_depth - 1;
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
    LLVMBuildBr(builder, step_bb);

  LLVMPositionBuilderAtEnd(builder, step_bb);
  cur_val := LLVMBuildLoad2(builder, var_llty, symbols[symi].llvm_val, MakeCStr(''));
  IF down THEN
    next_val := LLVMBuildSub(builder, cur_val, LLVMConstInt(var_llty, 1, 0), MakeCStr(''))
  ELSE
    next_val := LLVMBuildAdd(builder, cur_val, LLVMConstInt(var_llty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_val, symbols[symi].llvm_val);
  LLVMBuildBr(builder, loop_bb);
  IF GetObjOrNil(stmt, 'unroll') <> NIL THEN
    AttachUnrollHint(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)), GetInt(stmt, 'unroll'));

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE EmitByteCopyLoop(dest_ptr, src_ptr: ADRMEM; count: ADRMEM);
{ Copies `count` (an i32 LLVMValueRef) bytes one at a time from src_ptr to
  dest_ptr, via an alloca'd i32 loop counter -- the same alloca-based
  loop-variable idiom CodegenForStmt already uses, rather than building
  phi nodes by hand. Used by CONCAT/COPYLST/COPYSTR, whose source length is
  only known at runtime (an LSTRING's dynamic length byte), so the
  compile-time-known-literal shortcut CodegenLStringLiteralAssign/
  CodegenStringLiteralAssign use does not apply. }
VAR
  i_slot: ADRMEM;
  loop_bb, body_bb, end_bb: ADRMEM;
  cur_i, cmp_val, next_i: ADRMEM;
  s_ptr, d_ptr, byte_val: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  i_slot := EntryAlloca(i32ty, '');
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), i_slot);

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strcpy_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strcpy_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strcpy_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  cmp_val := LLVMBuildICmp(builder, LLVMIntSLT, cur_i, count, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, cur_i);
  s_ptr := LLVMBuildGEP2(builder, i8ty, src_ptr, gep_idx, 1, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, cur_i);
  d_ptr := LLVMBuildGEP2(builder, i8ty, dest_ptr, gep_idx, 1, MakeCStr(''));
  byte_val := LLVMBuildLoad2(builder, i8ty, s_ptr, MakeCStr(''));
  LLVMBuildStore(builder, byte_val, d_ptr);
  next_i := LLVMBuildAdd(builder, cur_i, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_i, i_slot);
  LLVMBuildBr(builder, loop_bb);

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE EmitByteFillLoop(dest_ptr: ADRMEM; count: ADRMEM; fill_byte: INTEGER);
{ Fills `count` (an i32 LLVMValueRef) bytes at dest_ptr with the constant
  byte fill_byte, via the same alloca-counter loop idiom as
  EmitByteCopyLoop. Used by COPYSTR's blank-padding (manual 11-20: bytes
  beyond the copied source, up to STRING's fixed capacity, get 0x20). }
VAR
  i_slot: ADRMEM;
  loop_bb, body_bb, end_bb: ADRMEM;
  cur_i, cmp_val, next_i: ADRMEM;
  d_ptr: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  i_slot := EntryAlloca(i32ty, '');
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), i_slot);

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strfill_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strfill_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strfill_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  cmp_val := LLVMBuildICmp(builder, LLVMIntSLT, cur_i, count, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, cur_i);
  d_ptr := LLVMBuildGEP2(builder, i8ty, dest_ptr, gep_idx, 1, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i8ty, fill_byte, 0), d_ptr);
  next_i := LLVMBuildAdd(builder, cur_i, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_i, i_slot);
  LLVMBuildBr(builder, loop_bb);

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenCopylst(args: ADRMEM);
{ COPYLST(CONST S: STRING-or-LSTRING-or-literal; VAR D: LSTRING): copies S's
  characters into D from scratch (unlike CONCAT, which appends) and sets D's
  length byte to length(S). No RANGECK-style capacity guard, same documented
  simplification as CONCAT. }
VAR
  d_arg: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, len_ptr, src_len_byte: ADRMEM;
  dest_chars: ADRMEM;
  src_chars, src_len: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: COPYLST expects exactly 2 arguments');
  d_arg := ArrItem(args, 1);
  IF NodeType(d_arg) <> 'Identifier' THEN
    AbortWith('codegen: COPYLST''s destination must be a bare LSTRING variable');
  d_symi := LookupSym(GetStr(d_arg, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(d_arg, 'name'));
  d_tid := symbols[d_symi].tk;
  IF TypeKind(d_tid) <> TK_LSTRING THEN
    AbortWith('codegen: COPYLST''s destination must be an LSTRING variable');
  d_addr := symbols[d_symi].llvm_val;

  ResolveStringExprCharsLen(ArrItem(args, 0), src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  dest_chars := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  EmitByteCopyLoop(dest_chars, src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  src_len_byte := LLVMBuildTrunc(builder, src_len, i8ty, MakeCStr(''));
  LLVMBuildStore(builder, src_len_byte, len_ptr);
END;

PROCEDURE CodegenCopystr(args: ADRMEM);
{ COPYSTR(CONST S: STRING-or-LSTRING-or-literal; VAR D: STRING): copies S's
  characters into D from byte[0], then blank-pads the remaining bytes (from
  length(S) up to D's fixed capacity) with 0x20 -- STRING has no length
  byte, so every declared byte always holds a real character. }
VAR
  d_arg: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr: ADRMEM;
  dest_chars, pad_ptr, pad_len: ADRMEM;
  src_chars, src_len: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: COPYSTR expects exactly 2 arguments');
  d_arg := ArrItem(args, 1);
  IF NodeType(d_arg) <> 'Identifier' THEN
    AbortWith('codegen: COPYSTR''s destination must be a bare STRING variable');
  d_symi := LookupSym(GetStr(d_arg, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(d_arg, 'name'));
  d_tid := symbols[d_symi].tk;
  IF TypeKind(d_tid) <> TK_STRING THEN
    AbortWith('codegen: COPYSTR''s destination must be a STRING variable');
  d_addr := symbols[d_symi].llvm_val;

  ResolveStringExprCharsLen(ArrItem(args, 0), src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  dest_chars := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  EmitByteCopyLoop(dest_chars, src_chars, src_len);

  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, src_len);
  pad_ptr := LLVMBuildGEP2(builder, i8ty, dest_chars, gep_idx, 1, MakeCStr(''));
  pad_len := LLVMBuildSub(builder, LLVMConstInt(i32ty, types[d_tid].hi, 0), src_len, MakeCStr(''));
  EmitByteFillLoop(pad_ptr, pad_len, 32);
END;

PROCEDURE CodegenInsert(args: ADRMEM);
{ INSERT(CONST S: STRING-or-LSTRING-or-literal; VAR D: LSTRING-or-STRING;
  pos: INTEGER): shifts D's existing characters from `pos` onward right by
  length(S) (via memmove, since the shifted range overlaps itself -- a
  plain byte-by-byte forward copy like EmitByteCopyLoop would corrupt
  overlapping data here), then writes S into the gap. Only updates the
  length-prefix byte when D is an LSTRING; a STRING destination has no
  length byte to update. No RANGECK-style capacity guard, same documented
  simplification as CONCAT/COPYLST/COPYSTR. }
VAR
  src_chars, src_len: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, dst_chars, dst_len: ADRMEM;
  pos_val, pos0, new_len, tail_len, shift_offset: ADRMEM;
  dst_start, shift_dest, len_ptr, new_len_byte: ADRMEM;
  gep_idx: ADRMEM;
  call_args: ADRMEM;
  discard: ADRMEM;
BEGIN
  IF ArrSize(args) <> 3 THEN
    AbortWith('codegen: INSERT expects exactly 3 arguments');
  ResolveStringExprCharsLen(ArrItem(args, 0), src_chars, src_len);
  ResolveStringDestVar(ArrItem(args, 1), d_symi, d_tid, d_addr, dst_chars, dst_len);

  pos_val := CodegenExpr(ArrItem(args, 2));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: INSERT''s position argument must be INTEGER');
  pos0 := LLVMBuildSExt(builder, pos_val, i32ty, MakeCStr(''));
  pos0 := LLVMBuildSub(builder, pos0, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));

  new_len := LLVMBuildAdd(builder, dst_len, src_len, MakeCStr(''));
  tail_len := LLVMBuildSub(builder, dst_len, pos0, MakeCStr(''));

  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, pos0);
  dst_start := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));

  shift_offset := LLVMBuildAdd(builder, pos0, src_len, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, shift_offset);
  shift_dest := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));

  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, shift_dest);
  SetPtrArrayElem(call_args, 1, dst_start);
  SetPtrArrayElem(call_args, 2, LLVMBuildZExt(builder, tail_len, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, call_args, 3, MakeCStr(''));

  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, dst_start);
  SetPtrArrayElem(call_args, 1, src_chars);
  SetPtrArrayElem(call_args, 2, LLVMBuildZExt(builder, src_len, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, call_args, 3, MakeCStr(''));

  IF TypeKind(d_tid) = TK_LSTRING THEN
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
    new_len_byte := LLVMBuildTrunc(builder, new_len, i8ty, MakeCStr(''));
    LLVMBuildStore(builder, new_len_byte, len_ptr);
  END;
END;

PROCEDURE CodegenDelete(args: ADRMEM);
{ DELETE(VAR D: LSTRING-or-STRING; pos, count: INTEGER): removes `count`
  characters starting at `pos` by memmove-ing the remaining tail left, and
  (LSTRING only) shrinks the length-prefix byte by `count`. }
VAR
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, dst_chars, dst_len: ADRMEM;
  pos_val, count_val, start, count32, rem, new_len: ADRMEM;
  src_off, len_ptr, new_len_byte: ADRMEM;
  dst_at_start, src_at_off: ADRMEM;
  gep_idx, call_args: ADRMEM;
  discard: ADRMEM;
BEGIN
  IF ArrSize(args) <> 3 THEN
    AbortWith('codegen: DELETE expects exactly 3 arguments');
  ResolveStringDestVar(ArrItem(args, 0), d_symi, d_tid, d_addr, dst_chars, dst_len);

  pos_val := CodegenExpr(ArrItem(args, 1));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: DELETE''s position argument must be INTEGER');
  count_val := CodegenExpr(ArrItem(args, 2));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: DELETE''s count argument must be INTEGER');

  start := LLVMBuildSExt(builder, pos_val, i32ty, MakeCStr(''));
  start := LLVMBuildSub(builder, start, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));
  count32 := LLVMBuildSExt(builder, count_val, i32ty, MakeCStr(''));

  src_off := LLVMBuildAdd(builder, start, count32, MakeCStr(''));
  rem := LLVMBuildSub(builder, dst_len, src_off, MakeCStr(''));

  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, start);
  dst_at_start := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, src_off);
  src_at_off := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));

  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, dst_at_start);
  SetPtrArrayElem(call_args, 1, src_at_off);
  SetPtrArrayElem(call_args, 2, LLVMBuildZExt(builder, rem, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, call_args, 3, MakeCStr(''));

  new_len := LLVMBuildSub(builder, dst_len, count32, MakeCStr(''));
  IF TypeKind(d_tid) = TK_LSTRING THEN
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
    new_len_byte := LLVMBuildTrunc(builder, new_len, i8ty, MakeCStr(''));
    LLVMBuildStore(builder, new_len_byte, len_ptr);
  END;
END;

PROCEDURE CodegenConcat(args: ADRMEM);
{ CONCAT(VAR D: LSTRING; CONST S: STRING): appends S's characters to D and
  grows D's length byte by length(S) -- manual 11-20. No RANGECK-style
  capacity guard yet (matches this file's documented MATHCK/RANGECK
  simplification elsewhere: a capacity overflow here just corrupts memory,
  same as an unchecked array index). }
VAR
  d_arg: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, len_ptr, dest_len_byte, dest_len, new_len, new_len_byte: ADRMEM;
  dest_chars, append_ptr: ADRMEM;
  src_chars, src_len: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: CONCAT expects exactly 2 arguments');
  d_arg := ArrItem(args, 0);
  IF NodeType(d_arg) <> 'Identifier' THEN
    AbortWith('codegen: CONCAT''s destination must be a bare LSTRING variable');
  d_symi := LookupSym(GetStr(d_arg, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(d_arg, 'name'));
  d_tid := symbols[d_symi].tk;
  IF TypeKind(d_tid) <> TK_LSTRING THEN
    AbortWith('codegen: CONCAT''s destination must be an LSTRING variable');
  d_addr := symbols[d_symi].llvm_val;

  ResolveStringExprCharsLen(ArrItem(args, 1), src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  dest_len_byte := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
  dest_len := LLVMBuildZExt(builder, dest_len_byte, i32ty, MakeCStr(''));
  new_len := LLVMBuildAdd(builder, dest_len, src_len, MakeCStr(''));

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  dest_chars := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, dest_len);
  append_ptr := LLVMBuildGEP2(builder, i8ty, dest_chars, gep_idx, 1, MakeCStr(''));
  EmitByteCopyLoop(append_ptr, src_chars, src_len);

  new_len_byte := LLVMBuildTrunc(builder, new_len, i8ty, MakeCStr(''));
  LLVMBuildStore(builder, new_len_byte, len_ptr);
END;

FUNCTION EmitLaunchThunk(ridx: INTEGER32): ADRMEM;
{ Emit the CPU-device entry adapter: void(i8** argv). Each argv slot points
  to a typed argument cell, exactly as pas_dev_launch expects. }
VAR
  thunk_name: Str255;
  thunk_ty, thunk, thunk_bb, saved_bb, saved_fn: ADRMEM;
  argv, slot_addr, slot, typed, val: ADRMEM;
  indices, call_args: ADRMEM;
  i: INTEGER32;
BEGIN
  thunk_name := '__pas_klaunch_';
  CONCAT(thunk_name, routines[ridx].name);
  thunk_ty := LLVMFunctionType(voidty, MakeArgs1(LLVMPointerType(i8ptrty, 0)), 1, 0);
  thunk := LLVMAddFunction(modl, MakeCStr(thunk_name), thunk_ty);
  LLVMSetLinkage(thunk, 8); { LLVMInternalLinkage -- reached only through the
                              registry, never by name from another object. }
  thunk_bb := LLVMAppendBasicBlockInContext(ctx, thunk, MakeCStr('entry'));
  saved_bb := LLVMGetInsertBlock(builder);
  saved_fn := cur_fn;
  LLVMPositionBuilderAtEnd(builder, thunk_bb);
  cur_fn := thunk;
  argv := LLVMGetParam(thunk, 0);
  call_args := AllocPtrArray(routines[ridx].nparams);
  FOR i := 0 TO routines[ridx].nparams - 1 DO
  BEGIN
    indices := AllocPtrArray(1);
    SetPtrArrayElem(indices, 0, LLVMConstInt(i32ty, i, 0));
    slot_addr := LLVMBuildGEP2(builder, i8ptrty, argv, indices, 1, MakeCStr(''));
    slot := LLVMBuildLoad2(builder, i8ptrty, slot_addr, MakeCStr(''));
    typed := LLVMBuildBitCast(builder, slot,
      LLVMPointerType(LLVMTypeForTk(routines[ridx].param_tk[i + 1]), 0), MakeCStr(''));
    val := LLVMBuildLoad2(builder, LLVMTypeForTk(routines[ridx].param_tk[i + 1]), typed, MakeCStr(''));
    SetPtrArrayElem(call_args, i, val);
  END;
  val := LLVMBuildCall2(builder, routines[ridx].fnty, routines[ridx].fn,
    call_args, routines[ridx].nparams, MakeCStr(''));
  LLVMBuildRetVoid(builder);
  cur_fn := saved_fn;
  LLVMPositionBuilderAtEnd(builder, saved_bb);
  EmitLaunchThunk := thunk;
END;

FUNCTION LaunchRegistryPtr: ADRMEM;
{ An i8* to this compiland's kernel registry global -- the CPU stand-in for a
  loaded CUDA module. The global is a shell here; EmitLaunchRegistry fills it
  once every LAUNCH has recorded its kernel. Under the CUDA backend there is
  no in-process registry (the kernel is the loaded PTX module and the shim
  ignores this argument), so a null pointer is passed rather than referencing
  a registry global nothing would define. }
VAR
  elems: ADRMEM;
BEGIN
  IF device_backend_cuda THEN
    LaunchRegistryPtr := LLVMConstPointerNull(i8ptrty)
  ELSE
  BEGIN
    IF klaunch_registry_gv = NIL THEN
    BEGIN
      elems := AllocPtrArray(3);
      SetPtrArrayElem(elems, 0, LLVMPointerType(i8ptrty, 0));
      SetPtrArrayElem(elems, 1, LLVMPointerType(i8ptrty, 0));
      SetPtrArrayElem(elems, 2, i64ty);
      klaunch_registry_ty := LLVMStructTypeInContext(ctx, elems, 3, 0);
      klaunch_registry_gv := LLVMAddGlobal(modl, klaunch_registry_ty, MakeCStr('__pas_klaunch_registry'));
      LLVMSetGlobalConstant(klaunch_registry_gv, 1);
    END;
    LaunchRegistryPtr := LLVMConstBitCast(klaunch_registry_gv, i8ptrty);
  END;
END;

FUNCTION DevicePtxPtr: ADRMEM;
{ An i8* to the device-PTX blob the loader consumes. The CPU device never
  executes it -- its "module" is the registry -- but the mechanism is always
  present so swapping in the CUDA shim is a pure runtime change. Under the
  CUDA backend the blob is an external symbol built from the device unit's
  own .ptx at link time, so the host object neither bakes the kernel text in
  nor depends on the device artifact. }
BEGIN
  IF device_ptx_gv = NIL THEN
  BEGIN
    IF device_backend_cuda THEN
    BEGIN
      device_ptx_gv := LLVMAddGlobal(modl, LLVMArrayType(i8ty, 0), MakeCStr('__pas_device_ptx'));
      LLVMSetGlobalConstant(device_ptx_gv, 1);
      device_ptx_ptr_val := LLVMConstBitCast(device_ptx_gv, i8ptrty);
    END
    ELSE
    BEGIN
      device_ptx_ptr_val := LLVMBuildGlobalStringPtr(builder, MakeCStr(''), MakeCStr('__pas_device_ptx'));
      device_ptx_gv := device_ptx_ptr_val;
    END;
  END;
  DevicePtxPtr := device_ptx_ptr_val;
END;

FUNCTION LaunchThunkFor(ridx: INTEGER32): ADRMEM;
{ The dispatch thunk for this kernel, emitted once and recorded in the
  registry. A second LAUNCH of the same kernel reuses it -- emitting it again
  would silently uniquify the symbol into a second, unregistered thunk. }
VAR
  i, found: INTEGER32;
  kname: Str255;
  thunk: ADRMEM;
BEGIN
  { The name is copied to a local before the comparison because this file's
    own string-comparison lowering (IsStringShapedExpr) recognizes only a
    bare identifier or literal as string-shaped: with a selector-bearing
    designator on *both* sides it falls through to the scalar path and
    rejects the operands outright. }
  kname := routines[ridx].name;
  found := 0;
  FOR i := 1 TO nkernels DO
    IF kernel_name_tab[i] = kname THEN found := i;
  IF found <> 0 THEN LaunchThunkFor := kernel_thunk_tab[found]
  ELSE
  BEGIN
    IF nkernels >= MAX_KERNELS THEN AbortWith('codegen: too many launched kernels');
    thunk := EmitLaunchThunk(ridx);
    nkernels := nkernels + 1;
    kernel_name_tab[nkernels] := kname;
    kernel_thunk_tab[nkernels] := thunk;
    LaunchThunkFor := thunk;
  END;
END;

PROCEDURE EmitLaunchRegistry;
{ Fill the registry global from the launched-kernel list: a names table, an
  entries (thunk) table, and the i8** names / i8** entries / i64 count
  struct the shim's by-name lookup walks. A no-op for a compiland that
  performed no launches, so launch-free output is unchanged. }
VAR
  names_vals, ent_vals, reg_fields: ADRMEM;
  names_gv, ent_gv: ADRMEM;
  i: INTEGER32;
BEGIN
  IF (klaunch_registry_gv <> NIL) AND (nkernels > 0) THEN
  BEGIN
    names_vals := AllocPtrArray(nkernels);
    ent_vals := AllocPtrArray(nkernels);
    FOR i := 1 TO nkernels DO
    BEGIN
      SetPtrArrayElem(names_vals, i - 1,
        LLVMBuildGlobalStringPtr(builder, MakeCStr(kernel_name_tab[i]), MakeCStr('kregname')));
      SetPtrArrayElem(ent_vals, i - 1, LLVMConstBitCast(kernel_thunk_tab[i], i8ptrty));
    END;
    names_gv := LLVMAddGlobal(modl, LLVMArrayType(i8ptrty, nkernels), MakeCStr('__pas_kregnames'));
    LLVMSetGlobalConstant(names_gv, 1);
    LLVMSetInitializer(names_gv, LLVMConstArray(i8ptrty, names_vals, nkernels));
    ent_gv := LLVMAddGlobal(modl, LLVMArrayType(i8ptrty, nkernels), MakeCStr('__pas_kregentries'));
    LLVMSetGlobalConstant(ent_gv, 1);
    LLVMSetInitializer(ent_gv, LLVMConstArray(i8ptrty, ent_vals, nkernels));
    reg_fields := AllocPtrArray(3);
    SetPtrArrayElem(reg_fields, 0, LLVMConstBitCast(names_gv, LLVMPointerType(i8ptrty, 0)));
    SetPtrArrayElem(reg_fields, 1, LLVMConstBitCast(ent_gv, LLVMPointerType(i8ptrty, 0)));
    SetPtrArrayElem(reg_fields, 2, LLVMConstInt(i64ty, nkernels, 0));
    LLVMSetInitializer(klaunch_registry_gv, LLVMConstStructInContext(ctx, reg_fields, 3, 0));
  END;
END;

PROCEDURE CodegenLaunch(args: ADRMEM);
{ Host launch ABI: LAUNCH(kernel, grid, block, actuals...) or its six-value
  geometry form. It uses the CPU shim's real void** ABI and a dispatch thunk. }
VAR
  kernel, actual: ADRMEM;
  kernel_name: Str255;
  ridx, n, expected, i: INTEGER32;
  grid, block, val, cell, argv, argv_ptr, thunk: ADRMEM;
  dev_module, entry: ADRMEM;
  geom: ARRAY[1..6] OF ADRMEM;
  actual_tk: INTEGER;
  indices, call_args: ADRMEM;
BEGIN
  n := ArrSize(args);
  IF n < 3 THEN AbortWith('codegen: LAUNCH needs kernel, grid, and block');
  kernel := ArrItem(args, 0);
  IF NodeType(kernel) <> 'Identifier' THEN
    AbortWith('codegen: LAUNCH kernel must be an identifier');
  kernel_name := GetStr(kernel, 'name');
  ridx := LookupRoutine(kernel_name);
  IF ridx = 0 THEN AbortWith2('codegen: unknown LAUNCH kernel: ', kernel_name);
  expected := routines[ridx].nparams;
  IF (n <> expected + 3) AND (n <> expected + 7) THEN
    AbortWith('codegen: LAUNCH expects 2 or 6 geometry values');
  IF n = expected + 3 THEN
  BEGIN
    grid := CodegenExpr(ArrItem(args, 1));
    grid := LaunchI64(grid, last_val_tk);
    block := CodegenExpr(ArrItem(args, 2));
    block := LaunchI64(block, last_val_tk);
    geom[1] := grid; geom[2] := LLVMConstInt(i64ty, 1, 0); geom[3] := LLVMConstInt(i64ty, 1, 0);
    geom[4] := block; geom[5] := LLVMConstInt(i64ty, 1, 0); geom[6] := LLVMConstInt(i64ty, 1, 0);
  END
  ELSE
    FOR i := 1 TO 6 DO
    BEGIN
      geom[i] := CodegenExpr(ArrItem(args, i));
      geom[i] := LaunchI64(geom[i], last_val_tk);
    END;
  argv := EntryAlloca(LLVMArrayType(i8ptrty, expected), 'launch_argv');
  FOR i := 0 TO expected - 1 DO
  BEGIN
    IF n = expected + 3 THEN actual := ArrItem(args, i + 3)
    ELSE actual := ArrItem(args, i + 7);
    val := CodegenExpr(actual);
    actual_tk := last_val_tk;
    val := CoerceForAssign(val, actual_tk, routines[ridx].param_tk[i + 1], actual, kernel_name);
    cell := EntryAlloca(LLVMTypeForTk(routines[ridx].param_tk[i + 1]), 'launch_arg');
    LLVMBuildStore(builder, val, cell);
    indices := AllocPtrArray(2);
    SetPtrArrayElem(indices, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(indices, 1, LLVMConstInt(i32ty, i, 0));
    indices := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, expected), argv, indices, 2, MakeCStr(''));
    val := LLVMBuildBitCast(builder, cell, i8ptrty, MakeCStr(''));
    LLVMBuildStore(builder, val, indices);
  END;
  indices := AllocPtrArray(2);
  SetPtrArrayElem(indices, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(indices, 1, LLVMConstInt(i32ty, 0, 0));
  argv_ptr := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, expected), argv, indices, 2, MakeCStr(''));
  { Resolve the entry the way the CUDA driver does -- load the module, then
    look the kernel up in it by name -- so the same call site serves both
    backends. On the CPU device the module is this compiland's registry and
    the resolved entry is the dispatch thunk; under the CUDA backend the
    module is the loaded PTX and the shim dispatches by name, so no thunk or
    registry is emitted at all (the host object then has no undefined kernel
    symbol and needs no separate host-ABI device compile). }
  IF NOT device_backend_cuda THEN thunk := LaunchThunkFor(ridx);
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, LaunchRegistryPtr);
  SetPtrArrayElem(call_args, 1, DevicePtxPtr);
  dev_module := LLVMBuildCall2(builder, module_load_fnty, module_load_fn, call_args, 2, MakeCStr(''));
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, dev_module);
  SetPtrArrayElem(call_args, 1, LLVMBuildGlobalStringPtr(builder, MakeCStr(kernel_name), MakeCStr('kname')));
  entry := LLVMBuildCall2(builder, module_getfn_fnty, module_getfn_fn, call_args, 2, MakeCStr(''));
  call_args := AllocPtrArray(8);
  SetPtrArrayElem(call_args, 0, entry);
  SetPtrArrayElem(call_args, 1, geom[1]);
  SetPtrArrayElem(call_args, 2, geom[2]);
  SetPtrArrayElem(call_args, 3, geom[3]);
  SetPtrArrayElem(call_args, 4, geom[4]);
  SetPtrArrayElem(call_args, 5, geom[5]);
  SetPtrArrayElem(call_args, 6, geom[6]);
  SetPtrArrayElem(call_args, 7, argv_ptr);
  val := LLVMBuildCall2(builder, launch_fnty, launch_fn, call_args, 8, MakeCStr(''));
END;

PROCEDURE CodegenDeviceSync(name: Str255);
{ DEVICE synchronization. CPU-device execution is serial, so SYNCTHREADS is
  a no-op there; NVPTX lowers it to the hardware block barrier. }
VAR
  fnty, fn: ADRMEM;
  discard: ADRMEM;
BEGIN
  IF name <> 'SYNCTHREADS' THEN
    AbortWith2('codegen: unknown device synchronization builtin: ', name);
  IF is_nvptx_device THEN
  BEGIN
    fnty := LLVMFunctionType(voidty, NIL, 0, 0);
    fn := LLVMGetNamedFunction(modl, MakeCStr('llvm.nvvm.barrier0'));
    IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('llvm.nvvm.barrier0'), fnty);
    discard := LLVMBuildCall2(builder, fnty, fn, NIL, 0, MakeCStr(''));
  END;
END;

FUNCTION CoerceToI8Ptr(v: ADRMEM; tk: INTEGER): ADRMEM;
{ A device orchestration address argument may already be the opaque i8*
  representation (ADRMEM, e.g. DEVALLOC's own result) or a typed ^T POINTER
  value; either way the shim's C signature wants a flat i8*. }
BEGIN
  IF tk = TK_ADRMEM THEN CoerceToI8Ptr := v
  ELSE CoerceToI8Ptr := LLVMBuildBitCast(builder, v, i8ptrty, MakeCStr(''));
END;

PROCEDURE CodegenDeviceOrchestration(name: Str255; args: ADRMEM);
{ Lower DEVCOPYTO/DEVCOPYFROM/DEVFREE (Milestone D, host-only) to the
  orchestration shim externs. Mirrors the Python reference's
  _codegen_device_orchestration (stmts.py). DEVALLOC is the expression-form
  sibling, handled in CodegenExpr's FuncCall dispatch. }
VAR
  a0, a1, nbytes, call_args: ADRMEM;
  tk0, tk1: INTEGER;
  discard: ADRMEM;
BEGIN
  IF is_device_compiland THEN
    AbortWith2('codegen: host-only and cannot appear in DEVICE code: ', name);
  IF (name = 'DEVCOPYTO') OR (name = 'DEVCOPYFROM') THEN
  BEGIN
    IF ArrSize(args) <> 3 THEN AbortWith2('codegen: expects 3 arguments: ', name);
    a0 := CodegenExpr(ArrItem(args, 0)); tk0 := last_val_tk;
    a1 := CodegenExpr(ArrItem(args, 1)); tk1 := last_val_tk;
    nbytes := CodegenExpr(ArrItem(args, 2)); nbytes := LaunchI64(nbytes, last_val_tk);
    call_args := AllocPtrArray(3);
    SetPtrArrayElem(call_args, 0, CoerceToI8Ptr(a0, tk0));
    SetPtrArrayElem(call_args, 1, CoerceToI8Ptr(a1, tk1));
    SetPtrArrayElem(call_args, 2, nbytes);
    IF name = 'DEVCOPYTO' THEN
      discard := LLVMBuildCall2(builder, dev_copy_to_fnty, dev_copy_to_fn, call_args, 3, MakeCStr(''))
    ELSE
      discard := LLVMBuildCall2(builder, dev_copy_from_fnty, dev_copy_from_fn, call_args, 3, MakeCStr(''));
  END
  ELSE IF name = 'DEVFREE' THEN
  BEGIN
    IF ArrSize(args) <> 1 THEN AbortWith2('codegen: expects 1 argument: ', name);
    a0 := CodegenExpr(ArrItem(args, 0)); tk0 := last_val_tk;
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, CoerceToI8Ptr(a0, tk0));
    discard := LLVMBuildCall2(builder, dev_free_fnty, dev_free_fn, call_args, 1, MakeCStr(''));
  END
  ELSE
    AbortWith2('codegen: unknown device orchestration builtin: ', name);
END;

PROCEDURE CodegenProcCallStmt(stmt: ADRMEM);
VAR
  name: Str255;
  discard: ADRMEM;
  args, arg0: ADRMEM;
  symi: INTEGER32;
  ptr_tid, pointee_tid: INTEGER;
  raw, casted, call_args, bound, bytes, header: ADRMEM;
  narg: INTEGER32;
  fcb_ptr, assign_chars, assign_len: ADRMEM;
BEGIN
  name := GetStr(stmt, 'name');
  IF name = 'LAUNCH' THEN
    CodegenLaunch(GetObj(stmt, 'args'))
  ELSE IF is_device_compiland AND (name = 'SYNCTHREADS') THEN
    CodegenDeviceSync(name)
  ELSE IF (name = 'DEVCOPYTO') OR (name = 'DEVCOPYFROM') OR (name = 'DEVFREE') THEN
    CodegenDeviceOrchestration(name, GetObj(stmt, 'args'))
  ELSE IF name = 'WRITELN' THEN
    CodegenWriteArgs(GetObj(stmt, 'args'), TRUE)
  ELSE IF name = 'WRITE' THEN
    CodegenWriteArgs(GetObj(stmt, 'args'), FALSE)
  ELSE IF (name = 'READLN') THEN
    CodegenReadArgs(GetObj(stmt, 'args'), TRUE)
  ELSE IF (name = 'READ') THEN
    CodegenReadArgs(GetObj(stmt, 'args'), FALSE)
  ELSE IF (name = 'READSET') THEN
    CodegenReadSet(GetObj(stmt, 'args'))
  ELSE IF (name = 'RESET') OR (name = 'REWRITE') OR (name = 'GET') OR
          (name = 'PUT') OR (name = 'CLOSE') OR (name = 'DISCARD') THEN
  BEGIN
    args := GetObj(stmt, 'args');
    arg0 := ArrItem(args, 0);
    fcb_ptr := LoadFileFcbPtr(GetStr(arg0, 'name'));
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, fcb_ptr);
    IF name = 'RESET' THEN
      discard := LLVMBuildCall2(builder, file_reset_fnty, file_reset_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'REWRITE' THEN
      discard := LLVMBuildCall2(builder, file_rewrite_fnty, file_rewrite_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'GET' THEN
      discard := LLVMBuildCall2(builder, file_get_fnty, file_get_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'PUT' THEN
      discard := LLVMBuildCall2(builder, file_put_fnty, file_put_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'CLOSE' THEN
      discard := LLVMBuildCall2(builder, file_close_fnty, file_close_fn, call_args, 1, MakeCStr(''))
    ELSE
      discard := LLVMBuildCall2(builder, file_discard_fnty, file_discard_fn, call_args, 1, MakeCStr(''));
  END
  ELSE IF name = 'ASSIGN' THEN
  BEGIN
    args := GetObj(stmt, 'args');
    arg0 := ArrItem(args, 0);
    fcb_ptr := LoadFileFcbPtr(GetStr(arg0, 'name'));
    ResolveStringExprCharsLen(ArrItem(args, 1), assign_chars, assign_len);
    call_args := AllocPtrArray(3);
    SetPtrArrayElem(call_args, 0, fcb_ptr);
    SetPtrArrayElem(call_args, 1, assign_chars);
    SetPtrArrayElem(call_args, 2, assign_len);
    discard := LLVMBuildCall2(builder, file_assign_fnty, file_assign_fn, call_args, 3, MakeCStr(''));
  END
  ELSE IF name = 'CONCAT' THEN
    CodegenConcat(GetObj(stmt, 'args'))
  ELSE IF name = 'COPYLST' THEN
    CodegenCopylst(GetObj(stmt, 'args'))
  ELSE IF name = 'COPYSTR' THEN
    CodegenCopystr(GetObj(stmt, 'args'))
  ELSE IF name = 'INSERT' THEN
    CodegenInsert(GetObj(stmt, 'args'))
  ELSE IF name = 'DELETE' THEN
    CodegenDelete(GetObj(stmt, 'args'))
  ELSE IF name = 'POSITN' THEN
    discard := CodegenPositn(GetObj(stmt, 'args'))
  ELSE IF name = 'SCANEQ' THEN
    discard := CodegenScan(1, GetObj(stmt, 'args'))
  ELSE IF name = 'SCANNE' THEN
    discard := CodegenScan(0, GetObj(stmt, 'args'))
  ELSE IF name = 'ENCODE' THEN
    discard := CodegenEncode(GetObj(stmt, 'args'))
  ELSE IF name = 'DECODE' THEN
    discard := CodegenDecode(GetObj(stmt, 'args'))
  ELSE IF (name = 'NEW') OR (name = 'DISPOSE') THEN
  BEGIN
    args := GetObj(stmt, 'args');
    narg := ArrSize(args);
    IF ((name = 'DISPOSE') AND (narg <> 1)) OR
       ((name = 'NEW') AND (narg <> 1) AND (narg <> 2)) THEN
      AbortWith2('codegen: wrong argument count for: ', name);
    arg0 := ArrItem(args, 0);
    IF NodeType(arg0) <> 'Identifier' THEN
      AbortWith2('codegen: argument must be a bare pointer variable: ', name);
    symi := LookupSym(GetStr(arg0, 'name'));
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', GetStr(arg0, 'name'));
    ptr_tid := symbols[symi].tk;
    IF TypeKind(ptr_tid) <> TK_POINTER THEN
      AbortWith2('codegen: argument is not a POINTER variable: ', name);
    IF name = 'NEW' THEN
    BEGIN
      pointee_tid := types[ptr_tid].elem_tid;
      call_args := AllocPtrArray(1);
      IF types[pointee_tid].is_super THEN
      BEGIN
        IF narg <> 2 THEN AbortWith('codegen: NEW of SUPER ARRAY needs an upper bound');
        bound := CodegenExpr(ArrItem(args, 1));
        bound := LaunchI64(bound, last_val_tk);
        { malloc holds an i64 upper-bound header followed by flat elements. }
        bytes := LLVMBuildAdd(builder, bound, LLVMConstInt(i64ty, 1 - types[pointee_tid].lo, 1), MakeCStr(''));
        bytes := LLVMBuildMul(builder, bytes, LLVMConstInt(i64ty, TypeSizeBytes(types[pointee_tid].elem_tid), 0), MakeCStr(''));
        bytes := LLVMBuildAdd(builder, bytes, LLVMConstInt(i64ty, 8, 0), MakeCStr(''));
        SetPtrArrayElem(call_args, 0, bytes);
        raw := LLVMBuildCall2(builder, malloc_fnty, malloc_fn, call_args, 1, MakeCStr(''));
        LLVMBuildStore(builder, bound, raw);
        header := LLVMBuildGEP2(builder, i8ty, raw, MakeArgs1(LLVMConstInt(i64ty, 8, 0)), 1, MakeCStr(''));
        casted := LLVMBuildBitCast(builder, header, LLVMTypeForTk(ptr_tid), MakeCStr(''));
      END
      ELSE
      BEGIN
        SetPtrArrayElem(call_args, 0, LLVMConstInt(i64ty, TypeSizeBytes(pointee_tid), 0));
        raw := LLVMBuildCall2(builder, malloc_fnty, malloc_fn, call_args, 1, MakeCStr(''));
        casted := LLVMBuildBitCast(builder, raw, LLVMTypeForTk(ptr_tid), MakeCStr(''));
      END;
      LLVMBuildStore(builder, casted, symbols[symi].llvm_val);
    END
    ELSE
    BEGIN
      raw := LLVMBuildLoad2(builder, LLVMTypeForTk(ptr_tid), symbols[symi].llvm_val, MakeCStr(''));
      casted := LLVMBuildBitCast(builder, raw, i8ptrty, MakeCStr(''));
      IF types[types[ptr_tid].elem_tid].is_super THEN
        casted := LLVMBuildGEP2(builder, i8ty, casted,
          MakeArgs1(LLVMConstInt(i64ty, -8, 1)), 1, MakeCStr(''));
      call_args := AllocPtrArray(1);
      SetPtrArrayElem(call_args, 0, casted);
      discard := LLVMBuildCall2(builder, free_fnty, free_fn, call_args, 1, MakeCStr(''));
    END;
  END
  ELSE
    discard := CodegenCallCommon(name, GetObj(stmt, 'args'));
END;

PROCEDURE CodegenReturnStmt(stmt: ADRMEM);
{ RETURN exits the current routine immediately with whatever value is
  currently held in the function's return-value alloca (the same slot
  `FuncName := ...` assigns and which the implicit end-of-body return also
  loads) -- it does not reset the result to a fixed constant. }
VAR
  ret_load: ADRMEM;
  ret_class, n_pieces: INTEGER;
  piece_kind: SysVPieceArr;
  piece_bytes: SysVPieceSzArr;
  cstruct_ty, cptr: ADRMEM;
BEGIN
  IF cur_func_name = '' THEN
    LLVMBuildRetVoid(builder)
  ELSE
  BEGIN
    { Aggregate returns are classified on demand from cur_func_ret_tk, same
      idiom as FuncRetAggClass -- so this can never disagree with the
      classification CodegenRoutineDecl already applied to cur_func_ret_slot
      itself (the sret pointer for MEMORY, or the over-aligned aggregate
      alloca for COERCED). Mirrors that procedure's own epilogue exactly. }
    ret_class := 0;
    IF IsAggregateTk(cur_func_ret_tk) THEN
      ClassifyAggregate(cur_func_ret_tk, ret_class, n_pieces, piece_kind, piece_bytes);
    IF ret_class = SYSV_CLASS_MEMORY THEN
      LLVMBuildRetVoid(builder)
    ELSE IF ret_class = SYSV_CLASS_COERCED THEN
    BEGIN
      cstruct_ty := SysVCoercedRetType(n_pieces, piece_kind, piece_bytes);
      cptr := LLVMBuildBitCast(builder, cur_func_ret_slot, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
      ret_load := LLVMBuildLoad2(builder, cstruct_ty, cptr, MakeCStr(''));
      LLVMSetAlignment(ret_load, 8);
      ret_load := LLVMBuildRet(builder, ret_load);
    END
    ELSE
    BEGIN
      ret_load := LLVMBuildLoad2(builder, LLVMTypeForTk(cur_func_ret_tk), cur_func_ret_slot, MakeCStr(''));
      ret_load := LLVMBuildRet(builder, ret_load);
    END;
  END;
END;

FUNCTION FindLabeledLoopDepth(lbl: Str255): INTEGER32;
{ Searches innermost-to-outermost (loop_depth downto 1) for the enclosing
  loop a labeled BREAK/CYCLE names -- matches the manual's BREAK <label>/
  CYCLE <label> targeting a specific enclosing loop, not just the
  innermost one. Returns 0 if no enclosing loop carries that label. }
VAR
  d: INTEGER32;
BEGIN
  FindLabeledLoopDepth := 0;
  FOR d := loop_depth DOWNTO 1 DO
    IF loop_labels[d] = lbl THEN
    BEGIN
      FindLabeledLoopDepth := d;
      BREAK;
    END;
END;

PROCEDURE CodegenBreakStmt(stmt: ADRMEM);
VAR
  lbl: Str255;
  d: INTEGER32;
BEGIN
  IF loop_depth = 0 THEN
    AbortWith('codegen: BREAK outside of a loop');
  IF GetObjOrNil(stmt, 'label') = NIL THEN
    LLVMBuildBr(builder, loop_break_blocks[loop_depth])
  ELSE
  BEGIN
    lbl := LabelKey(stmt, 'label');
    d := FindLabeledLoopDepth(lbl);
    IF d = 0 THEN AbortWith2('codegen: BREAK targets a label with no enclosing loop: ', lbl);
    LLVMBuildBr(builder, loop_break_blocks[d]);
  END;
END;

PROCEDURE CodegenCycleStmt(stmt: ADRMEM);
VAR
  lbl: Str255;
  d: INTEGER32;
BEGIN
  IF loop_depth = 0 THEN
    AbortWith('codegen: CYCLE outside of a loop');
  IF GetObjOrNil(stmt, 'label') = NIL THEN
    LLVMBuildBr(builder, loop_cycle_blocks[loop_depth])
  ELSE
  BEGIN
    lbl := LabelKey(stmt, 'label');
    d := FindLabeledLoopDepth(lbl);
    IF d = 0 THEN AbortWith2('codegen: CYCLE targets a label with no enclosing loop: ', lbl);
    LLVMBuildBr(builder, loop_cycle_blocks[d]);
  END;
END;

PROCEDURE CodegenGotoStmt(stmt: ADRMEM);
VAR
  lbl: Str255;
  li: INTEGER32;
BEGIN
  lbl := LabelKey(stmt, 'label');
  li := LookupLabel(lbl);
  IF li = 0 THEN
    AbortWith2('codegen: GOTO to undefined label (routine-local only): ', lbl);
  LLVMBuildBr(builder, labels[li].block);
END;

PROCEDURE CodegenLabelStmt(stmt: ADRMEM);
{ The label's block was already allocated by SetupFunctionLabels before this
  routine's body was codegen'd (so a forward GOTO higher up could already
  reference it). Branch into it from the current position if not already
  terminated, then continue codegen'ing the inner statement there. If that
  inner statement is itself a loop, hand its label down via
  pending_loop_label so a labeled BREAK/CYCLE elsewhere can target it. }
VAR
  lbl: Str255;
  li: INTEGER32;
  inner: ADRMEM;
  inner_nt: Str255;
BEGIN
  lbl := LabelKey(stmt, 'label');
  li := LookupLabel(lbl);
  IF li = 0 THEN
    AbortWith2('codegen: internal error: label block missing: ', lbl);
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
    LLVMBuildBr(builder, labels[li].block);
  LLVMPositionBuilderAtEnd(builder, labels[li].block);
  inner := GetObj(stmt, 'stmt');
  inner_nt := NodeType(inner);
  IF (inner_nt = 'WhileStmt') OR (inner_nt = 'RepeatStmt') OR (inner_nt = 'ForStmt') THEN
    pending_loop_label := lbl;
  CodegenStmt(inner);
END;

PROCEDURE CodegenWithStmt(stmt: ADRMEM);
{ WITH t1, t2, ... DO body: one PushScope per target left to right, each
  target's fields registered directly as symbols whose llvm_val IS the
  field's own GEP'd storage address (not a copy) -- so reads/writes inside
  body affect the underlying record in place, matching the reference's
  "bind field name directly to GEP pointer" (codegen/stmts.py's
  codegen_with_stmt). A later target's field of the same name shadows an
  earlier one for free, since LookupSym's backward scan finds the most
  recently appended symbol first. }
VAR
  targets, target: ADRMEM;
  ntargets, ti, fi: INTEGER32;
  base_ptr, field_ptr, gep_idx: ADRMEM;
  cur_tid: INTEGER;
  pushed: INTEGER32;
BEGIN
  targets := GetObj(stmt, 'targets');
  ntargets := ArrSize(targets);
  pushed := 0;
  FOR ti := 0 TO ntargets - 1 DO
  BEGIN
    target := ArrItem(targets, ti);
    base_ptr := ComputeDesignatorAddress(target);
    cur_tid := last_val_tk;
    IF TypeKind(cur_tid) <> TK_RECORD THEN
      AbortWith('codegen: WITH target must be a record');
    PushScope;
    pushed := pushed + 1;
    FOR fi := 1 TO nfields DO
      IF fields[fi].rec_tid = cur_tid THEN
      BEGIN
        gep_idx := AllocPtrArray(1);
        SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, fields[fi].byte_offset, 0));
        field_ptr := LLVMBuildGEP2(builder, i8ty, base_ptr, gep_idx, 1, MakeCStr(''));
        field_ptr := LLVMBuildBitCast(builder, field_ptr, LLVMPointerType(LLVMTypeForTk(fields[fi].field_tid), 0), MakeCStr(''));
        IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
        nsymbols := nsymbols + 1;
        symbols[nsymbols].name := fields[fi].fname;
        symbols[nsymbols].tk := fields[fi].field_tid;
        symbols[nsymbols].llvm_val := field_ptr;
      END;
  END;
  CodegenStmt(GetObj(stmt, 'body'));
  FOR ti := 1 TO pushed DO
    PopScope;
END;

PROCEDURE CodegenStmt(stmt: ADRMEM);
VAR
  nt, msg: Str255;
BEGIN
  EnterStmtLevel;
  nt := NodeType(stmt);
  IF nt = 'AssignStmt' THEN CodegenAssignStmt(stmt)
  ELSE IF nt = 'CompoundStmt' THEN CodegenStmtArray(GetObj(stmt, 'stmts'))
  ELSE IF nt = 'IfStmt' THEN CodegenIfStmt(stmt)
  ELSE IF nt = 'WhileStmt' THEN CodegenWhileStmt(stmt)
  ELSE IF nt = 'RepeatStmt' THEN CodegenRepeatStmt(stmt)
  ELSE IF nt = 'ForStmt' THEN CodegenForStmt(stmt)
  ELSE IF nt = 'CaseStmt' THEN CodegenCaseStmt(stmt)
  ELSE IF nt = 'ProcCallStmt' THEN CodegenProcCallStmt(stmt)
  ELSE IF nt = 'ReturnStmt' THEN CodegenReturnStmt(stmt)
  ELSE IF nt = 'BreakStmt' THEN CodegenBreakStmt(stmt)
  ELSE IF nt = 'CycleStmt' THEN CodegenCycleStmt(stmt)
  ELSE IF nt = 'LabelStmt' THEN CodegenLabelStmt(stmt)
  ELSE IF nt = 'GotoStmt' THEN CodegenGotoStmt(stmt)
  ELSE IF nt = 'WithStmt' THEN CodegenWithStmt(stmt)
  ELSE IF nt = 'EmptyStmt' THEN BEGIN END
  ELSE
  BEGIN
    msg := 'codegen: unhandled statement kind: ';
    CONCAT(msg, nt);
    AbortWith(msg);
  END;
  LeaveStmtLevel;
END;


BEGIN
END.
