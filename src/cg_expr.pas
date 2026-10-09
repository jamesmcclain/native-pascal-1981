{ Implementations for cg_expr. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
(*$INCLUDE:'cg_expr_shape.inc'*)
(*$INCLUDE:'cg_expr_sets.inc'*)
(*$INCLUDE:'cg_expr_support.inc'*)
(*$INCLUDE:'cg_expr_literals.inc'*)
(*$INCLUDE:'cg_expr_vector.inc'*)
(*$INCLUDE:'cg_expr.inc'*)
IMPLEMENTATION OF cg_expr;
USES cg_expr_shape, cg_expr_sets, cg_expr_support, cg_expr_literals, cg_expr_vector;

FUNCTION CodegenExpr(node: ADRMEM): ADRMEM; FORWARD;
FUNCTION ComputeDesignatorAddress(node: ADRMEM): ADRMEM; FORWARD;
FUNCTION CodegenPositn(args: ADRMEM): ADRMEM; FORWARD;
FUNCTION CodegenScan(stop_on_equal: INTEGER; args: ADRMEM): ADRMEM; FORWARD;
FUNCTION CodegenEncode(args: ADRMEM): ADRMEM; FORWARD;
FUNCTION CodegenDecode(args: ADRMEM): ADRMEM; FORWARD;
FUNCTION CodegenOverflowOk(nm: Str255; args: ADRMEM): ADRMEM; FORWARD;
PROCEDURE ResolveStringExprCharsLen(expr: ADRMEM; VAR chars_ptr: ADRMEM; VAR len_val: ADRMEM); FORWARD;

{ ============================== expressions =============================== }


{ ------------------------------ sets --------------------------------------
  Every SET, regardless of its declared base range, is represented the same
  physical way the Python reference represents it: a fixed 256-bit bitvector
  (setty = [4 x i64]), ordinal N's bit living at word N DIV 64, bit N MOD 64.
  Unlike the reference, nothing here is constant-folded at compile time --
  every element (even a literal like `[1, 2, 3]`) is set via a real runtime
  OR-in instruction sequence. That is behaviorally identical and much
  simpler to implement correctly than carrying a parallel compile-time-words
  accumulator through SetConstructor the way strings.py does, at the cost of
  a few more instructions in the emitted IR -- an acceptable tradeoff given
  this file's methodology is behavioral parity, not IR-shape parity. }

FUNCTION SetElementOutside(v: ADRMEM): ADRMEM;
{ TRUE when the i16 set ordinal v is outside 0..255. The compare is
  unsigned, so a negative ordinal is outside too. }
BEGIN
  SetElementOutside := LLVMBuildICmp(builder, LLVMIntUGT, v,
    LLVMConstInt(i16ty, 255, 0), MakeCStr(''));
END;

PROCEDURE EmitSetElementCheck(bad, v: ADRMEM);
{ A set is a 256-bit bitvector, so when bad holds, call the noreturn
  pas_set_element_error (runtime/set_element.c) with the i16 ordinal v from
  a cold block instead of setting a bit outside the set. Leaves the builder
  in the in-range block. Device code has no host runtime to call, so it is
  not checked. }
VAR
  bad_bb, ok_bb, ps, fnty, fn, args, discard: ADRMEM;
BEGIN
  IF is_nvptx_device THEN RETURN;
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('setelem.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('setelem.ok'));
  LLVMBuildCondBr(builder, bad, bad_bb, ok_bb);

  LLVMPositionBuilderAtEnd(builder, bad_bb);
  ps := AllocPtrArray(1);
  SetPtrArrayElem(ps, 0, i64ty);
  fnty := LLVMFunctionType(voidty, ps, 1, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_set_element_error'));
  IF fn = NIL THEN
    fn := LLVMAddFunction(modl, MakeCStr('pas_set_element_error'), fnty);
  args := AllocPtrArray(1);
  SetPtrArrayElem(args, 0, LLVMBuildSExt(builder, v, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, fnty, fn, args, 1, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);

  LLVMPositionBuilderAtEnd(builder, ok_bb);
END;

PROCEDURE EmitSetRangeLoop(slot: ADRMEM; low_node, high_node: ADRMEM);
{ FOR i := low TO high DO SetRuntimeBit(slot, i) -- same alloca-counter loop
  idiom as CodegenForStmt/EmitByteCopyLoop, done here instead of reusing
  CodegenForStmt directly since there is no surface-syntax FOR loop AST node
  to hand it (RangeExpr's bounds are arbitrary compatible ordinal expressions,
  not necessarily a declared loop variable). A reversed range is empty. }
VAR
  low_val, high_val: ADRMEM;
  i_slot: ADRMEM;
  loop_bb, body_bb, end_bb: ADRMEM;
  cur_i, cmp_val, next_i: ADRMEM;
  low_bad, bad: ADRMEM;
BEGIN
  low_val := CodegenExpr(low_node);
  IF (last_val_tk = TK_CHAR) OR (last_val_tk = TK_BOOLEAN) THEN
    low_val := LLVMBuildZExt(builder, low_val, i16ty, MakeCStr(''))
  ELSE IF TypeKind(last_val_tk) = TK_ENUM THEN
    low_val := LLVMBuildTrunc(builder, low_val, i16ty, MakeCStr(''))
  ELSE IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: a set range bound must be INTEGER, CHAR, BOOLEAN or an enumeration');
  high_val := CodegenExpr(high_node);
  IF (last_val_tk = TK_CHAR) OR (last_val_tk = TK_BOOLEAN) THEN
    high_val := LLVMBuildZExt(builder, high_val, i16ty, MakeCStr(''))
  ELSE IF TypeKind(last_val_tk) = TK_ENUM THEN
    high_val := LLVMBuildTrunc(builder, high_val, i16ty, MakeCStr(''))
  ELSE IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: a set range bound must be INTEGER, CHAR, BOOLEAN or an enumeration');

  { A nonempty range must lie in 0..255; this also keeps the i16 counter
    from wrapping past 32767. An empty (reversed) range adds nothing. }
  low_bad := SetElementOutside(low_val);
  bad := LLVMBuildAnd(builder,
    LLVMBuildICmp(builder, LLVMIntSLE, low_val, high_val, MakeCStr('')),
    LLVMBuildOr(builder, low_bad, SetElementOutside(high_val), MakeCStr('')),
    MakeCStr(''));
  EmitSetElementCheck(bad,
    LLVMBuildSelect(builder, low_bad, low_val, high_val, MakeCStr('')));

  i_slot := EntryAlloca(i16ty, '');
  LLVMBuildStore(builder, low_val, i_slot);

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('setrange_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('setrange_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('setrange_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_i := LLVMBuildLoad2(builder, i16ty, i_slot, MakeCStr(''));
  cmp_val := LLVMBuildICmp(builder, LLVMIntSLE, cur_i, high_val, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  cur_i := LLVMBuildLoad2(builder, i16ty, i_slot, MakeCStr(''));
  SetRuntimeBit(slot, cur_i);
  next_i := LLVMBuildAdd(builder, cur_i, LLVMConstInt(i16ty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_i, i_slot);
  LLVMBuildBr(builder, loop_bb);

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

FUNCTION CodegenSetConstructor(node: ADRMEM): ADRMEM;
VAR
  slot: ADRMEM;
  elements, el: ADRMEM;
  n, i: INTEGER32;
  ordv: ADRMEM;
BEGIN
  slot := EntryAlloca(setty, '');
  LLVMBuildStore(builder, LLVMConstNull(setty), slot);
  elements := GetObj(node, 'elements');
  n := ArrSize(elements);
  FOR i := 0 TO n - 1 DO
  BEGIN
    el := ArrItem(elements, i);
    IF NodeType(el) = 'RangeExpr' THEN
      EmitSetRangeLoop(slot, GetObj(el, 'low'), GetObj(el, 'high'))
    ELSE
    BEGIN
      ordv := CodegenExpr(el);
      IF (last_val_tk = TK_CHAR) OR (last_val_tk = TK_BOOLEAN) THEN
        ordv := LLVMBuildZExt(builder, ordv, i16ty, MakeCStr(''))
      ELSE IF TypeKind(last_val_tk) = TK_ENUM THEN
        ordv := LLVMBuildTrunc(builder, ordv, i16ty, MakeCStr(''))
      ELSE IF last_val_tk <> TK_INTEGER THEN
        AbortWith('codegen: a set element must be INTEGER, CHAR, BOOLEAN or an enumeration');
      EmitSetElementCheck(SetElementOutside(ordv), ordv);
      SetRuntimeBit(slot, ordv);
    END;
  END;
  CodegenSetConstructor := LLVMBuildLoad2(builder, setty, slot, MakeCStr(''));
  last_val_tk := EnsureGenericSetType;
END;


FUNCTION CodegenStringBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
{ Whole-string EQ/NEQ/LT/LE/GT/GE, matching the reference's
  codegen_string_binop: compare min(len)-many bytes via memcmp, then fold
  in the length comparison the same way lexicographic ordering does. }
VAR
  l_chars, l_len, r_chars, r_len: ADRMEM;
  min_len, min_len64, cmp_res, cmp_call_args: ADRMEM;
  cmp_eq0, len_eq, len_lt, len_gt, cmp_lt0, cmp_gt0, res: ADRMEM;
BEGIN
  ResolveStringExprCharsLen(left_node, l_chars, l_len);
  ResolveStringExprCharsLen(right_node, r_chars, r_len);
  min_len := LLVMBuildSelect(builder, LLVMBuildICmp(builder, LLVMIntSLT, l_len, r_len, MakeCStr('')), l_len, r_len, MakeCStr(''));
  min_len64 := LLVMBuildZExt(builder, min_len, i64ty, MakeCStr(''));
  cmp_call_args := AllocPtrArray(3);
  SetPtrArrayElem(cmp_call_args, 0, l_chars);
  SetPtrArrayElem(cmp_call_args, 1, r_chars);
  SetPtrArrayElem(cmp_call_args, 2, min_len64);
  cmp_res := LLVMBuildCall2(builder, memcmp_fnty, memcmp_fn, cmp_call_args, 3, MakeCStr(''));
  cmp_eq0 := LLVMBuildICmp(builder, LLVMIntEQ, cmp_res, LLVMConstInt(i32ty, 0, 1), MakeCStr(''));
  len_eq := LLVMBuildICmp(builder, LLVMIntEQ, l_len, r_len, MakeCStr(''));
  IF op = 'EQ' THEN
    res := LLVMBuildAnd(builder, cmp_eq0, len_eq, MakeCStr(''))
  ELSE IF op = 'NEQ' THEN
    res := LLVMBuildNot(builder, LLVMBuildAnd(builder, cmp_eq0, len_eq, MakeCStr('')), MakeCStr(''))
  ELSE IF op = 'LT' THEN
  BEGIN
    len_lt := LLVMBuildICmp(builder, LLVMIntSLT, l_len, r_len, MakeCStr(''));
    cmp_lt0 := LLVMBuildICmp(builder, LLVMIntSLT, cmp_res, LLVMConstInt(i32ty, 0, 1), MakeCStr(''));
    res := LLVMBuildOr(builder, cmp_lt0, LLVMBuildAnd(builder, cmp_eq0, len_lt, MakeCStr('')), MakeCStr(''));
  END
  ELSE IF op = 'LE' THEN
  BEGIN
    len_lt := LLVMBuildICmp(builder, LLVMIntSLE, l_len, r_len, MakeCStr(''));
    cmp_lt0 := LLVMBuildICmp(builder, LLVMIntSLT, cmp_res, LLVMConstInt(i32ty, 0, 1), MakeCStr(''));
    res := LLVMBuildOr(builder, cmp_lt0, LLVMBuildAnd(builder, cmp_eq0, len_lt, MakeCStr('')), MakeCStr(''));
  END
  ELSE IF op = 'GT' THEN
  BEGIN
    len_gt := LLVMBuildICmp(builder, LLVMIntSGT, l_len, r_len, MakeCStr(''));
    cmp_gt0 := LLVMBuildICmp(builder, LLVMIntSGT, cmp_res, LLVMConstInt(i32ty, 0, 1), MakeCStr(''));
    res := LLVMBuildOr(builder, cmp_gt0, LLVMBuildAnd(builder, cmp_eq0, len_gt, MakeCStr('')), MakeCStr(''));
  END
  ELSE IF op = 'GE' THEN
  BEGIN
    len_gt := LLVMBuildICmp(builder, LLVMIntSGE, l_len, r_len, MakeCStr(''));
    cmp_gt0 := LLVMBuildICmp(builder, LLVMIntSGT, cmp_res, LLVMConstInt(i32ty, 0, 1), MakeCStr(''));
    res := LLVMBuildOr(builder, cmp_gt0, LLVMBuildAnd(builder, cmp_eq0, len_gt, MakeCStr('')), MakeCStr(''));
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unsupported string comparison operator: ', op);
    res := NIL;
  END;
  CodegenStringBinOp := res;
END;

FUNCTION CodegenShortCircuitBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
{ AND THEN / OR ELSE: the right operand must not be evaluated at all when
  the left already decides the result -- e.g. typechecker.pas's own
  `(i >= 1) AND THEN (symbols[i].name <> name)` relies on this to avoid
  indexing symbols[0] out of bounds. Mirrors the reference's
  codegen_short_circuit_binop: branch on the left value, only enter a
  second block to evaluate the right operand, then phi the two paths
  together instead of eagerly computing both operands up front. }
VAR
  left_val, right_val, short_val, phi: ADRMEM;
  rhs_bb, merge_bb, left_bb, right_bb: ADRMEM;
  incoming_vals, incoming_blocks: ADRMEM;
BEGIN
  left_val := CodegenExpr(left_node);
  rhs_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('sc_rhs'));
  merge_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('sc_merge'));
  IF op = 'AND_THEN' THEN
  BEGIN
    LLVMBuildCondBr(builder, left_val, rhs_bb, merge_bb);
    short_val := LLVMConstInt(i1ty, 0, 0);
  END
  ELSE
  BEGIN
    LLVMBuildCondBr(builder, left_val, merge_bb, rhs_bb);
    short_val := LLVMConstInt(i1ty, 1, 0);
  END;
  left_bb := LLVMGetInsertBlock(builder);

  LLVMPositionBuilderAtEnd(builder, rhs_bb);
  right_val := CodegenExpr(right_node);
  right_bb := LLVMGetInsertBlock(builder);
  LLVMBuildBr(builder, merge_bb);

  LLVMPositionBuilderAtEnd(builder, merge_bb);
  phi := LLVMBuildPhi(builder, i1ty, MakeCStr('sc_result'));
  incoming_vals := AllocPtrArray(2);
  SetPtrArrayElem(incoming_vals, 0, short_val);
  SetPtrArrayElem(incoming_vals, 1, right_val);
  incoming_blocks := AllocPtrArray(2);
  SetPtrArrayElem(incoming_blocks, 0, left_bb);
  SetPtrArrayElem(incoming_blocks, 1, right_bb);
  LLVMAddIncoming(phi, incoming_vals, incoming_blocks, 2);
  last_val_tk := TK_BOOLEAN;
  CodegenShortCircuitBinOp := phi;
END;

PROCEDURE OperationLocation(site: ADRMEM; VAR line, column: INTEGER32);
{ An operation's diagnostic coordinates come only from its own node's
  parser snapshot. A legacy node without one reports line 0 column 0. }
VAR
  location: ADRMEM;
BEGIN
  line := 0;
  column := 0;
  IF HasKey(site, 'op_location') THEN
  BEGIN
    location := GetObj(site, 'op_location');
    line := GetInt(location, 'line');
    column := GetInt(location, 'column');
  END;
END;

FUNCTION SiteMathCk(site: ADRMEM): BOOLEAN;
{ MATHCK+ comes only from the operation's own parser snapshot; a legacy
  node without one is unchecked. Never ask a flags object: cJSON keys are
  case-insensitive, so its MATHCK entry would also match mathck. }
VAR
  enabled: BOOLEAN;
BEGIN
  enabled := FALSE;
  IF site <> NIL THEN
    IF HasKey(site, 'mathck') THEN enabled := GetBool(site, 'mathck');
  SiteMathCk := enabled;
END;

PROCEDURE MathckDeviceBoundary(site: ADRMEM);
{ NVPTX DEVICE code has no host failure path, so an operation that MATHCK+
  would check is rejected before any IR is published, per the approved
  unsupported-boundary policy (docs/dialect_notes.md, MATHCK). MATHCK- at the
  operation is the opt-out. CPU DEVICE code shares the host failure path
  and is checked normally. }
VAR
  msg: Str255;
  line, column: INTEGER32;
BEGIN
  msg := 'MATHCK unsupported boundary: DEVICE arithmetic';
  OperationLocation(site, line, column);
  IF (line > 0) AND (column > 0) THEN
  BEGIN
    CONCAT(msg, ' at line ');
    CONCAT(msg, InitckIntText(line));
    CONCAT(msg, ' column ');
    CONCAT(msg, InitckIntText(column));
  END;
  AbortWith(msg);
END;

FUNCTION MathReportOperand(v: ADRMEM; tk: INTEGER): ADRMEM;
{ An already-evaluated operand widened to i64 with its own signedness. }
BEGIN
  IF IntFamilyWidth(tk) = 64 THEN MathReportOperand := v
  ELSE IF IsUnsignedWordTk(tk) THEN
    MathReportOperand := LLVMBuildZExt(builder, v, i64ty, MakeCStr(''))
  ELSE
    MathReportOperand := LLVMBuildSExt(builder, v, i64ty, MakeCStr(''));
END;

PROCEDURE EmitMathOverflowCheck(failed: ADRMEM; op_code: INTEGER;
  lval, rval: ADRMEM; tk: INTEGER; site: ADRMEM);
{ Branch on failed to a noreturn pas_math_overflow call before the result
  is stored or used, then continue in math.ok. op_code follows
  runtime/mathck.c: 0 +, 1 -, 2 *, 3 DIV, 4 unary -. rval is NIL for a
  unary operation and is reported as 0 (the runtime ignores it). }
VAR
  bad_bb, ok_bb, ps, fnty, fn, args, discard: ADRMEM;
  line, column: INTEGER32;
BEGIN
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('math.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('math.ok'));
  LLVMBuildCondBr(builder, failed, bad_bb, ok_bb);
  LLVMPositionBuilderAtEnd(builder, bad_bb);
  ps := AllocPtrArray(6);
  SetPtrArrayElem(ps, 0, i32ty);
  SetPtrArrayElem(ps, 1, i32ty);
  SetPtrArrayElem(ps, 2, i64ty);
  SetPtrArrayElem(ps, 3, i64ty);
  SetPtrArrayElem(ps, 4, i32ty);
  SetPtrArrayElem(ps, 5, i32ty);
  fnty := LLVMFunctionType(voidty, ps, 6, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_math_overflow'));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_math_overflow'), fnty);
  OperationLocation(site, line, column);
  args := AllocPtrArray(6);
  IF IsUnsignedWordTk(tk) THEN SetPtrArrayElem(args, 0, LLVMConstInt(i32ty, 1, 0))
  ELSE SetPtrArrayElem(args, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, op_code, 0));
  SetPtrArrayElem(args, 2, MathReportOperand(lval, tk));
  IF rval = NIL THEN SetPtrArrayElem(args, 3, LLVMConstInt(i64ty, 0, 0))
  ELSE SetPtrArrayElem(args, 3, MathReportOperand(rval, tk));
  SetPtrArrayElem(args, 4, LLVMConstInt(i32ty, line, 0));
  SetPtrArrayElem(args, 5, LLVMConstInt(i32ty, column, 0));
  discard := LLVMBuildCall2(builder, fnty, fn, args, 6, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
END;

FUNCTION FoldedOperationTk(site: ADRMEM): INTEGER;
{ The integer type the typechecker resolved for a fully constant + - * DIV
  MOD or negation after range-checking its exact folded value
  (CheckFoldedOperation); TK_UNKNOWN for any other node, including a
  legacy typed AST without the tag. }
VAR
  tag: ADRMEM;
  name: Str255;
  tk: INTEGER;
BEGIN
  tk := TK_UNKNOWN;
  tag := GetObjOrNil(site, 'resolved_type');
  IF (tag <> NIL) AND IsIntLiteralLike(site) THEN
  BEGIN
    name := GetStr(tag, '__type_system__');
    IF name = 'IntegerType' THEN tk := TK_INTEGER
    ELSE IF name = 'WordType' THEN tk := TK_WORD
    ELSE IF name = 'Integer8Type' THEN tk := TK_INTEGER8
    ELSE IF name = 'Word8Type' THEN tk := TK_WORD8
    ELSE IF name = 'Integer32Type' THEN tk := TK_INTEGER32
    ELSE IF name = 'Word32Type' THEN tk := TK_WORD32
    ELSE IF name = 'Integer64Type' THEN tk := TK_INTEGER64
    ELSE IF name = 'Word64Type' THEN tk := TK_WORD64;
  END;
  FoldedOperationTk := tk;
END;

FUNCTION TcFoldedOperation(site: ADRMEM): BOOLEAN;
{ TRUE only for an operation the typechecker folded and range-checked
  (CheckFoldedOperation tagged its type). Codegen's own folder accepts more
  (enum members, for example), and such an operation, which nothing has
  checked, is checked at run time like any other. }
BEGIN
  TcFoldedOperation := FoldedOperationTk(site) <> TK_UNKNOWN;
END;

FUNCTION OverflowIntrinsicCall(op: Str255; lval, rval: ADRMEM; tk: INTEGER): ADRMEM;
{ The (result, overflow) pair of the LLVM sadd/ssub/smul.with.overflow
  intrinsic, or uadd/usub/umul for the WORD family, at tk's width. }
VAR
  name: Str255;
  ty, elems, pair_ty, ps, fnty, fn, args: ADRMEM;
  width: INTEGER;
BEGIN
  IF IsUnsignedWordTk(tk) THEN name := 'llvm.u' ELSE name := 'llvm.s';
  IF op = 'PLUS' THEN CONCAT(name, 'add')
  ELSE IF op = 'MINUS' THEN CONCAT(name, 'sub')
  ELSE CONCAT(name, 'mul');
  width := IntFamilyWidth(tk);
  IF width = 8 THEN CONCAT(name, '.with.overflow.i8')
  ELSE IF width = 16 THEN CONCAT(name, '.with.overflow.i16')
  ELSE IF width = 32 THEN CONCAT(name, '.with.overflow.i32')
  ELSE CONCAT(name, '.with.overflow.i64');
  ty := LLVMTypeForTk(tk);
  elems := AllocPtrArray(2);
  SetPtrArrayElem(elems, 0, ty);
  SetPtrArrayElem(elems, 1, i1ty);
  pair_ty := LLVMStructTypeInContext(ctx, elems, 2, 0);
  ps := AllocPtrArray(2);
  SetPtrArrayElem(ps, 0, ty);
  SetPtrArrayElem(ps, 1, ty);
  fnty := LLVMFunctionType(pair_ty, ps, 2, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr(name));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr(name), fnty);
  args := AllocPtrArray(2);
  SetPtrArrayElem(args, 0, lval);
  SetPtrArrayElem(args, 1, rval);
  OverflowIntrinsicCall := LLVMBuildCall2(builder, fnty, fn, args, 2, MakeCStr('math'));
END;

FUNCTION CodegenCheckedArith(op: Str255; lval, rval: ADRMEM; tk: INTEGER;
  site: ADRMEM): ADRMEM;
{ MATHCK+ scalar + - * at the adapted/promoted operand width and
  signedness, so overflow is the exact result leaving the resolved type's
  native range (INTEGER -32768 is a valid result). The failure branch
  precedes any use of the result. }
VAR
  pair: ADRMEM;
  op_code: INTEGER;
BEGIN
  IF op = 'PLUS' THEN op_code := 0
  ELSE IF op = 'MINUS' THEN op_code := 1
  ELSE op_code := 2;
  pair := OverflowIntrinsicCall(op, lval, rval, tk);
  EmitMathOverflowCheck(LLVMBuildExtractValue(builder, pair, 1, MakeCStr('math.ovf')),
    op_code, lval, rval, tk, site);
  CodegenCheckedArith := LLVMBuildExtractValue(builder, pair, 0, MakeCStr(''));
END;

FUNCTION CodegenCheckedUnary(op: Str255; lval, rval, operand: ADRMEM;
  op_code, tk: INTEGER; site: ADRMEM): ADRMEM;
{ A MATHCK+ one-operand operation lowered as the checked lval op rval
  (negation is 0 - v, SUCC/PRED are v + 1 and v - 1); the failure reports
  only the source operand. }
VAR
  pair: ADRMEM;
BEGIN
  pair := OverflowIntrinsicCall(op, lval, rval, tk);
  EmitMathOverflowCheck(LLVMBuildExtractValue(builder, pair, 1, MakeCStr('math.ovf')),
    op_code, operand, NIL, tk, site);
  CodegenCheckedUnary := LLVMBuildExtractValue(builder, pair, 0, MakeCStr(''));
END;

FUNCTION CodegenCheckedNegate(v: ADRMEM; tk: INTEGER; site: ADRMEM): ADRMEM;
{ MATHCK+ unary minus as a checked 0 - v: signed MIN overflows; for the
  WORD family only zero negates without overflow. }
BEGIN
  CodegenCheckedNegate := CodegenCheckedUnary('MINUS',
    LLVMConstInt(LLVMTypeForTk(tk), 0, 0), v, v, 4, tk, site);
END;

PROCEDURE EmitSuccPredDomainCheck(v: ADRMEM; tid: INTEGER; is_succ: BOOLEAN);
{ $RANGECK for SUCC/PRED of a CHAR, BOOLEAN or enumeration value: the
  result has the argument's type (IBM 11-8), so stepping past its last
  (SUCC) or first (PRED) ordinal fails before the step. The report uses
  the ordinal the step would have produced. }
VAR
  lo, hi, edge: INTEGER32;
  ty, at_edge, bad_bb, ok_bb: ADRMEM;
  k: INTEGER;
BEGIN
  k := TypeKind(tid);
  IF k = TK_CHAR THEN
  BEGIN
    lo := 0; hi := 255; ty := i8ty;
  END
  ELSE IF k = TK_BOOLEAN THEN
  BEGIN
    lo := 0; hi := 1; ty := i1ty;
  END
  ELSE
  BEGIN
    lo := types[tid].lo; hi := types[tid].hi; ty := i32ty;
  END;
  IF is_succ THEN edge := hi ELSE edge := lo;
  at_edge := LLVMBuildICmp(builder, LLVMIntEQ, v, LLVMConstInt(ty, edge, 0), MakeCStr(''));
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('range.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('range.ok'));
  LLVMBuildCondBr(builder, at_edge, bad_bb, ok_bb);
  LLVMPositionBuilderAtEnd(builder, bad_bb);
  IF is_succ THEN edge := edge + 1 ELSE edge := edge - 1;
  EmitSubrangeFailure(LLVMConstInt(i64ty, edge, 1), FALSE, lo, hi);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
END;

FUNCTION SuccPredDomainTid(node: ADRMEM): INTEGER;
{ The declared type of a SUCC/PRED argument when it is evident before
  lowering: a variable or designator, or a nested SUCC/PRED, whose result
  has its argument's type. 0 otherwise. }
VAR
  nt, nm: Str255;
  symi: INTEGER32;
  args: ADRMEM;
  tid: INTEGER;
BEGIN
  tid := 0;
  nt := NodeType(node);
  IF (nt = 'Identifier') OR (nt = 'Designator') THEN
  BEGIN
    symi := LookupSym(GetStr(node, 'name'));
    IF symi <> 0 THEN
    BEGIN
      tid := symbols[symi].tk;
      IF nt = 'Designator' THEN tid := StaticDesigTid(tid, GetObj(node, 'selectors'));
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    nm := UpperStr(GetStr(node, 'name'));
    args := GetObj(node, 'args');
    IF ((nm = 'SUCC') OR (nm = 'PRED')) AND NOT UserRoutineShadows(nm) THEN
      IF ArrSize(args) = 1 THEN tid := SuccPredDomainTid(ArrItem(args, 0));
  END;
  SuccPredDomainTid := tid;
END;

FUNCTION CodegenSuccPred(is_succ: BOOLEAN; v: ADRMEM; argtk: INTEGER; site: ADRMEM): ADRMEM;
{ SUCC/PRED on an evaluated argument, at the argument's own type and
  width. Integer family: MATHCK+ (from the call's own snapshot) fails when
  the base type's extreme is stepped past; otherwise the step wraps.
  CHAR, BOOLEAN and enumerations: their ordinal range is RANGECK's, per
  statement like store checks. The result has the argument's type (IBM
  11-8), so a subrange argument whose type is evident (SuccPredDomainTid)
  is checked against its declared bounds after the step under RANGECK;
  any other subrange value arrives as its host type and is checked where
  it is stored. Base overflow is checked first. A fully constant call was
  range-checked by the typechecker and is materialized at its resolved
  type. }
VAR
  folded_tk, op_code, dom_tid: INTEGER;
  one, res: ADRMEM;
  op: Str255;
BEGIN
  IF is_succ THEN
  BEGIN
    op := 'PLUS'; op_code := 5;
  END
  ELSE
  BEGIN
    op := 'MINUS'; op_code := 6;
  END;
  folded_tk := FoldedOperationTk(site);
  IF folded_tk <> TK_UNKNOWN THEN
  BEGIN
    res := LLVMConstInt(LLVMTypeForTk(folded_tk), IntLiteralValue(site), 1);
    last_val_tk := folded_tk;
  END
  ELSE
  BEGIN
    IF IsIntegerFamilyTk(TypeKind(argtk)) THEN
    BEGIN
      one := LLVMConstInt(LLVMTypeForTk(TypeKind(argtk)), 1, 0);
      IF SiteMathCk(site) AND is_nvptx_device THEN MathckDeviceBoundary(site);
      IF SiteMathCk(site) AND NOT is_nvptx_device THEN
        res := CodegenCheckedUnary(op, v, one, v, op_code, TypeKind(argtk), site)
      ELSE IF is_succ THEN res := LLVMBuildAdd(builder, v, one, MakeCStr(''))
      ELSE res := LLVMBuildSub(builder, v, one, MakeCStr(''));
    END
    ELSE
    BEGIN
      IF cur_rangeck AND NOT is_nvptx_device THEN EmitSuccPredDomainCheck(v, argtk, is_succ);
      IF argtk = TK_CHAR THEN one := LLVMConstInt(i8ty, 1, 0)
      ELSE IF argtk = TK_BOOLEAN THEN one := LLVMConstInt(i1ty, 1, 0)
      ELSE one := LLVMConstInt(i32ty, 1, 0);
      IF is_succ THEN res := LLVMBuildAdd(builder, v, one, MakeCStr(''))
      ELSE res := LLVMBuildSub(builder, v, one, MakeCStr(''));
    END;
    dom_tid := SuccPredDomainTid(ArrItem(GetObj(site, 'args'), 0));
    IF dom_tid >= 14 THEN EmitSubrangeCheck(res, argtk, dom_tid);
    last_val_tk := argtk;
  END;
  CodegenSuccPred := res;
END;

FUNCTION CodegenSafeDivMod(op: Str255; lval, rval: ADRMEM; tk: INTEGER;
  site: ADRMEM): ADRMEM;
{ The zero-divisor test is mandatory, independent of MATHCK, and comes
  first. Under the operation's MATHCK+ snapshot, signed MIN DIV -1 then
  fails as overflow; unchecked, it returns MIN. MIN MOD -1 is always the
  valid result 0. Both errors report the operator token's coordinates.
  Sanitize the divisor even in a constant-dead block, so LLVM never sees
  a constant zero divisor or signed MIN/-1 in a division instruction. }
VAR
  ty, zero, one, iszero, exceptional, unsafe, safe_divisor, minval: ADRMEM;
  bad_bb, ok_bb, ps, fnty, fn, args, discard, result: ADRMEM;
  unsigned_value: BOOLEAN;
  line, column: INTEGER32;
BEGIN
  IF is_nvptx_device THEN
    AbortWith('codegen: scalar DIV/MOD safety is unsupported on DEVICE');
  unsigned_value := IsUnsignedWordTk(tk);
  ty := LLVMTypeForTk(tk);
  zero := LLVMConstInt(ty, 0, 0);
  one := LLVMConstInt(ty, 1, 0);
  iszero := LLVMBuildICmp(builder, LLVMIntEQ, rval, zero, MakeCStr('div.zero'));
  exceptional := LLVMConstInt(i1ty, 0, 0);
  minval := zero;
  IF NOT unsigned_value THEN
  BEGIN
    minval := LLVMBuildShl(builder, one,
      LLVMConstInt(ty, IntFamilyWidth(tk) - 1, 0), MakeCStr(''));
    exceptional := LLVMBuildAnd(builder,
      LLVMBuildICmp(builder, LLVMIntEQ, lval, minval, MakeCStr('')),
      LLVMBuildICmp(builder, LLVMIntEQ, rval, LLVMConstInt(ty, -1, 1), MakeCStr('')),
      MakeCStr('div.min'));
  END;
  unsafe := LLVMBuildOr(builder, iszero, exceptional, MakeCStr(''));
  safe_divisor := LLVMBuildSelect(builder, unsafe, one, rval, MakeCStr('div.safe'));
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('div.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('div.ok'));
  LLVMBuildCondBr(builder, iszero, bad_bb, ok_bb);
  LLVMPositionBuilderAtEnd(builder, bad_bb);
  ps := AllocPtrArray(6);
  SetPtrArrayElem(ps, 0, i32ty);
  SetPtrArrayElem(ps, 1, i32ty);
  SetPtrArrayElem(ps, 2, i64ty);
  SetPtrArrayElem(ps, 3, i64ty);
  SetPtrArrayElem(ps, 4, i32ty);
  SetPtrArrayElem(ps, 5, i32ty);
  fnty := LLVMFunctionType(voidty, ps, 6, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_math_zero'));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_math_zero'), fnty);
  args := AllocPtrArray(6);
  OperationLocation(site, line, column);
  SetPtrArrayElem(args, 4, LLVMConstInt(i32ty, line, 0));
  SetPtrArrayElem(args, 5, LLVMConstInt(i32ty, column, 0));
  IF unsigned_value THEN
  BEGIN
    SetPtrArrayElem(args, 0, LLVMConstInt(i32ty, 1, 0));
    IF IntFamilyWidth(tk) < 64 THEN
    BEGIN
      SetPtrArrayElem(args, 2, LLVMBuildZExt(builder, lval, i64ty, MakeCStr('')));
      SetPtrArrayElem(args, 3, LLVMBuildZExt(builder, rval, i64ty, MakeCStr('')));
    END;
  END
  ELSE
  BEGIN
    SetPtrArrayElem(args, 0, LLVMConstInt(i32ty, 0, 0));
    IF IntFamilyWidth(tk) < 64 THEN
    BEGIN
      SetPtrArrayElem(args, 2, LLVMBuildSExt(builder, lval, i64ty, MakeCStr('')));
      SetPtrArrayElem(args, 3, LLVMBuildSExt(builder, rval, i64ty, MakeCStr('')));
    END;
  END;
  IF IntFamilyWidth(tk) = 64 THEN
  BEGIN
    SetPtrArrayElem(args, 2, lval);
    SetPtrArrayElem(args, 3, rval);
  END;
  IF op = 'MOD' THEN SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, 1, 0))
  ELSE SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, 0, 0));
  discard := LLVMBuildCall2(builder, fnty, fn, args, 6, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
  { A quotient the typechecker folded is range-checked there instead. }
  IF (op = 'DIV') AND NOT unsigned_value AND SiteMathCk(site) AND
     NOT TcFoldedOperation(site) THEN
    EmitMathOverflowCheck(exceptional, 3, lval, rval, tk, site);
  IF unsigned_value THEN
  BEGIN
    IF op = 'DIV' THEN result := LLVMBuildUDiv(builder, lval, safe_divisor, MakeCStr(''))
    ELSE result := LLVMBuildURem(builder, lval, safe_divisor, MakeCStr(''));
  END
  ELSE
  BEGIN
    IF op = 'DIV' THEN
    BEGIN
      result := LLVMBuildSDiv(builder, lval, safe_divisor, MakeCStr(''));
      result := LLVMBuildSelect(builder, exceptional, minval, result, MakeCStr(''));
    END
    ELSE
    BEGIN
      result := LLVMBuildSRem(builder, lval, safe_divisor, MakeCStr(''));
      result := LLVMBuildSelect(builder, exceptional, zero, result, MakeCStr(''));
    END;
  END;
  CodegenSafeDivMod := result;
END;

FUNCTION CodegenLanesIntOp(op: Str255; lval, rval: ADRMEM; vec_tid: INTEGER;
  site: ADRMEM): ADRMEM;
{ An integer VECTOR operation one lane at a time, in lane order, through the
  scalar paths: checked + - * (op PLUS/MINUS/MUL) and negation (op NEG,
  rval unused) under the operation's MATHCK+ snapshot, and DIV/MOD with the
  mandatory zero-divisor failure and safe MIN/-1 under either setting. A
  failing lane reports its own operands at the operator's coordinates, and
  no lane result is used before every earlier lane has passed. }
VAR
  elem: INTEGER;
  i, n: INTEGER32;
  acc, idx, l, r, e: ADRMEM;
BEGIN
  elem := types[vec_tid].elem_tid;
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  acc := LLVMGetUndef(LLVMTypeForTk(vec_tid));
  FOR i := 0 TO n - 1 DO
  BEGIN
    idx := LLVMConstInt(i32ty, i, 0);
    l := LLVMBuildExtractElement(builder, lval, idx, MakeCStr(''));
    IF op = 'NEG' THEN
      e := CodegenCheckedNegate(l, elem, site)
    ELSE
    BEGIN
      r := LLVMBuildExtractElement(builder, rval, idx, MakeCStr(''));
      IF (op = 'DIV') OR (op = 'MOD') THEN
        e := CodegenSafeDivMod(op, l, r, elem, site)
      ELSE
        e := CodegenCheckedArith(op, l, r, elem, site);
    END;
    acc := LLVMBuildInsertElement(builder, acc, e, idx, MakeCStr(''));
  END;
  CodegenLanesIntOp := acc;
END;

FUNCTION VectorOverflowPair(op: Str255; lval, rval: ADRMEM; vec_tid: INTEGER): ADRMEM;
{ The (result vector, overflow lane mask) pair of the vector form of the LLVM
  sadd/ssub/smul.with.overflow (uadd/usub/umul for WORD lanes) at the
  vector type vec_tid. }
VAR
  name: Str255;
  elem: INTEGER;
  n: INTEGER32;
  vecty, elems, pair_ty, ps, fnty, fn, args: ADRMEM;
BEGIN
  elem := types[vec_tid].elem_tid;
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  IF IsUnsignedWordTk(elem) THEN name := 'llvm.u' ELSE name := 'llvm.s';
  IF op = 'PLUS' THEN CONCAT(name, 'add')
  ELSE IF op = 'MINUS' THEN CONCAT(name, 'sub')
  ELSE CONCAT(name, 'mul');
  CONCAT(name, '.with.overflow.v');
  CONCAT(name, InitckIntText(n));
  IF IntFamilyWidth(elem) = 8 THEN CONCAT(name, 'i8')
  ELSE IF IntFamilyWidth(elem) = 16 THEN CONCAT(name, 'i16')
  ELSE IF IntFamilyWidth(elem) = 32 THEN CONCAT(name, 'i32')
  ELSE CONCAT(name, 'i64');
  vecty := LLVMTypeForTk(vec_tid);
  elems := AllocPtrArray(2);
  SetPtrArrayElem(elems, 0, vecty);
  SetPtrArrayElem(elems, 1, LLVMVectorType(i1ty, n));
  pair_ty := LLVMStructTypeInContext(ctx, elems, 2, 0);
  ps := AllocPtrArray(2);
  SetPtrArrayElem(ps, 0, vecty);
  SetPtrArrayElem(ps, 1, vecty);
  fnty := LLVMFunctionType(pair_ty, ps, 2, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr(name));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr(name), fnty);
  args := AllocPtrArray(2);
  SetPtrArrayElem(args, 0, lval);
  SetPtrArrayElem(args, 1, rval);
  VectorOverflowPair := LLVMBuildCall2(builder, fnty, fn, args, 2, MakeCStr('vmath'));
END;

FUNCTION CodegenLanewiseIntOp(op: Str255; lval, rval: ADRMEM; vec_tid: INTEGER;
  site: ADRMEM): ADRMEM;
{ Integer VECTOR + - * and negation under MATHCK+, and DIV/MOD under either
  setting. DIV/MOD go lane by lane (CodegenLanesIntOp). + - * and
  negation (0 - v) compute every lane at once with the vector overflow
  intrinsic and branch once on the OR of its overflow lanes; only when
  some lane overflowed does the cold path redo the operation lane by lane,
  so the lowest failing lane traps with its own operands exactly as
  before. The fast path's result is used only after that branch. }
VAR
  elem: INTEGER;
  n: INTEGER32;
  lhs, rhs, pair, mask, any, ps, fnty, fn, args, slow_bb, ok_bb, discard: ADRMEM;
  kind, name: Str255;
BEGIN
  IF (op = 'DIV') OR (op = 'MOD') THEN
  BEGIN
    CodegenLanewiseIntOp := CodegenLanesIntOp(op, lval, rval, vec_tid, site);
    RETURN;
  END;
  elem := types[vec_tid].elem_tid;
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  IF op = 'NEG' THEN
  BEGIN
    kind := 'MINUS';
    lhs := LLVMConstNull(LLVMTypeForTk(vec_tid));
    rhs := lval;
  END
  ELSE
  BEGIN
    kind := op;
    lhs := lval;
    rhs := rval;
  END;
  pair := VectorOverflowPair(kind, lhs, rhs, vec_tid);
  mask := LLVMBuildExtractValue(builder, pair, 1, MakeCStr('vmath.ovf'));
  name := 'llvm.vector.reduce.or.v';
  CONCAT(name, InitckIntText(n));
  CONCAT(name, 'i1');
  ps := AllocPtrArray(1);
  SetPtrArrayElem(ps, 0, LLVMVectorType(i1ty, n));
  fnty := LLVMFunctionType(i1ty, ps, 1, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr(name));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr(name), fnty);
  args := AllocPtrArray(1);
  SetPtrArrayElem(args, 0, mask);
  any := LLVMBuildCall2(builder, fnty, fn, args, 1, MakeCStr('vmath.any'));
  slow_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('vmath.lanes'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('vmath.ok'));
  LLVMBuildCondBr(builder, any, slow_bb, ok_bb);
  LLVMPositionBuilderAtEnd(builder, slow_bb);
  discard := CodegenLanesIntOp(op, lval, rval, vec_tid, site);
  discard := LLVMBuildUnreachable(builder);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
  CodegenLanewiseIntOp := LLVMBuildExtractValue(builder, pair, 0, MakeCStr(''));
END;

FUNCTION CodegenCheckedVReduce(nm: Str255; vec_val: ADRMEM; vec_tid: INTEGER;
  site: ADRMEM): ADRMEM;
{ MATHCK+ integer VSUM/VPROD: a left-to-right fold over the lanes, each
  step checked at the element type. A failure reports the partial result
  so far and the lane value (op 9 VSUM, 10 VPROD in runtime/mathck.c). }
VAR
  elem, op_code: INTEGER;
  i, n: INTEGER32;
  acc, lane, pair: ADRMEM;
  op: Str255;
BEGIN
  elem := types[vec_tid].elem_tid;
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  IF nm = 'VSUM' THEN
  BEGIN
    op := 'PLUS';
    op_code := 9;
  END
  ELSE
  BEGIN
    op := 'MUL';
    op_code := 10;
  END;
  acc := LLVMBuildExtractElement(builder, vec_val, LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
  FOR i := 1 TO n - 1 DO
  BEGIN
    lane := LLVMBuildExtractElement(builder, vec_val, LLVMConstInt(i32ty, i, 0), MakeCStr(''));
    pair := OverflowIntrinsicCall(op, acc, lane, elem);
    EmitMathOverflowCheck(LLVMBuildExtractValue(builder, pair, 1, MakeCStr('math.ovf')),
      op_code, acc, lane, elem, site);
    acc := LLVMBuildExtractValue(builder, pair, 0, MakeCStr(''));
  END;
  last_val_tk := elem;
  CodegenCheckedVReduce := acc;
END;

FUNCTION ConstantAdaptsToOperand(const_node, other_node: ADRMEM;
  const_tk, other_tk: INTEGER): BOOLEAN;
{ Codegen's copy of the typechecker's ConstantAdaptsToOperand
  (src/tc_expr.pas) for a constant beside a nonconstant operand: the
  constant takes an unsigned operand's type (IBM's WORD constant rule), and
  a signed operand's type when it fits. Only an operand at least as wide:
  the typechecker's result type is the wider one, so a wider constant
  (WORD32 + an INTEGER64 CONST) instead widens the operand below. Nested
  IFs, because AND evaluates both sides and IntLiteralValue aborts on a
  nonconstant. }
VAR
  v: INTEGER64;
BEGIN
  ConstantAdaptsToOperand := FALSE;
  IF IsIntLiteralLike(const_node) AND (IntFamilyWidth(const_tk) <= IntFamilyWidth(other_tk)) THEN
    IF NOT IsIntLiteralLike(other_node) THEN
    BEGIN
      v := IntLiteralValue(const_node);
      IF IsUnsignedWordTk(other_tk) THEN ConstantAdaptsToOperand := TRUE
      ELSE IF other_tk = TK_INTEGER8 THEN ConstantAdaptsToOperand := (v >= -128) AND (v <= 127)
      ELSE IF other_tk = TK_INTEGER THEN ConstantAdaptsToOperand := (v >= -32768) AND (v <= 32767)
      ELSE IF other_tk = TK_INTEGER32 THEN
        ConstantAdaptsToOperand := (v >= -2147483647 - 1) AND (v <= 2147483647)
      ELSE ConstantAdaptsToOperand := other_tk = TK_INTEGER64;
    END;
END;

FUNCTION CodegenMixedSignCompare(op: Str255; lval, rval: ADRMEM;
  left_unsigned: BOOLEAN; common_tk: INTEGER): ADRMEM;
{ Exact relational between one INTEGER-family and one WORD-family operand,
  already extended to a common width (the signed side sign-extended, the
  unsigned side zero-extended; common_tk is either operand kind of that
  width). IBM leaves the mixture's signedness
  arbitrary (a warning); here the mathematical values are compared: a
  negative signed operand is below every unsigned value, otherwise the two
  bit patterns compare unsigned. No wider type is needed, so 64-bit pairs
  and DEVICE code take the same path. }
VAR
  s, u, neg, nonneg, cmp: ADRMEM;
  sop: Str255;
BEGIN
  { Normalize to `s sop u` with the signed operand on the left. }
  sop := op;
  IF left_unsigned THEN
  BEGIN
    s := rval; u := lval;
    IF op = 'LT' THEN sop := 'GT'
    ELSE IF op = 'LE' THEN sop := 'GE'
    ELSE IF op = 'GT' THEN sop := 'LT'
    ELSE IF op = 'GE' THEN sop := 'LE';
  END
  ELSE
  BEGIN
    s := lval; u := rval;
  END;
  neg := LLVMBuildICmp(builder, LLVMIntSLT, s, LLVMConstNull(LLVMTypeForTk(common_tk)), MakeCStr(''));
  nonneg := LLVMBuildNot(builder, neg, MakeCStr(''));
  IF sop = 'EQ' THEN cmp := LLVMBuildICmp(builder, LLVMIntEQ, s, u, MakeCStr(''))
  ELSE IF sop = 'NEQ' THEN cmp := LLVMBuildICmp(builder, LLVMIntNE, s, u, MakeCStr(''))
  ELSE IF sop = 'LT' THEN cmp := LLVMBuildICmp(builder, LLVMIntULT, s, u, MakeCStr(''))
  ELSE IF sop = 'LE' THEN cmp := LLVMBuildICmp(builder, LLVMIntULE, s, u, MakeCStr(''))
  ELSE IF sop = 'GT' THEN cmp := LLVMBuildICmp(builder, LLVMIntUGT, s, u, MakeCStr(''))
  ELSE cmp := LLVMBuildICmp(builder, LLVMIntUGE, s, u, MakeCStr(''));
  IF (sop = 'NEQ') OR (sop = 'LT') OR (sop = 'LE') THEN
    CodegenMixedSignCompare := LLVMBuildOr(builder, neg, cmp, MakeCStr(''))
  ELSE
    CodegenMixedSignCompare := LLVMBuildAnd(builder, nonneg, cmp, MakeCStr(''));
END;

FUNCTION NegativeConstBesideUnsigned(op: Str255; const_node: ADRMEM;
  other_tk: INTEGER): BOOLEAN;
{ A negative constant in a relational beside a WORD-family operand must not
  adapt to that operand's type: as WORD, -1 would be 0xFFFF and `w > -1`
  would be FALSE. Leaving it signed sends the comparison to the exact
  signed/unsigned path (CodegenMixedSignCompare), so a constant and a
  variable holding the same value compare alike. Nested IFs, because AND
  evaluates both sides and IntLiteralValue aborts on a nonconstant. }
BEGIN
  NegativeConstBesideUnsigned := FALSE;
  IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE') THEN
    IF IsUnsignedWordTk(other_tk) AND IsIntLiteralLike(const_node) THEN
      NegativeConstBesideUnsigned := IntLiteralValue(const_node) < 0;
END;

FUNCTION CodegenBinOp(op: Str255; left_node, right_node, site: ADRMEM): ADRMEM;
{ site is the BinOp node itself: per-operation metadata is read from it. }
VAR
  lval, rval, res: ADRMEM;
  ltk, rtk, folded_tk: INTEGER;
  gep_idx, ptr_elem_ty: ADRMEM;
  mixed_sign_cmp, left_neg_const, right_neg_const: BOOLEAN;
BEGIN
  IF (op = 'AND_THEN') OR (op = 'OR_ELSE') THEN
    res := CodegenShortCircuitBinOp(op, left_node, right_node)
  ELSE IF ((op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE'))
      AND (IsStringShapedExpr(left_node) OR IsStringShapedExpr(right_node)) THEN
  BEGIN
    res := CodegenStringBinOp(op, left_node, right_node);
    last_val_tk := TK_BOOLEAN;
  END
  ELSE
  BEGIN
  lval := CodegenExpr(left_node);
  ltk := last_val_tk;
  rval := CodegenExpr(right_node);
  rtk := last_val_tk;

  { A fully constant operation is the typechecker's exact folded value at
    its checked type. Its operands are still generated first (constants
    only, so no code), which keeps the expression depth limit in force. }
  folded_tk := FoldedOperationTk(site);
  IF folded_tk <> TK_UNKNOWN THEN
  BEGIN
    res := LLVMConstInt(LLVMTypeForTk(folded_tk), IntLiteralValue(site), 1);
    last_val_tk := folded_tk;
  END
  ELSE
  BEGIN
  { A bare INTEGER literal operand adapts to the other side's wider/
    differently-signed integer type, mirroring the reference's
    literal_context threading (typecheck/exprs.py): CodegenExpr always
    builds an IntLiteral as plain 16-bit INTEGER with no knowledge of
    context, so rebuild it at the sibling operand's own width here instead
    of letting the ltk<>rtk check below reject it as "mixed-type". }
  mixed_sign_cmp := FALSE;
  left_neg_const := NegativeConstBesideUnsigned(op, left_node, rtk);
  right_neg_const := NegativeConstBesideUnsigned(op, right_node, ltk);
  IF (op = 'SLASH') AND IsIntegerFamilyTk(ltk) AND IsIntegerFamilyTk(rtk) THEN
  BEGIN
    { SLASH is always real division in Pascal (7/2 = 3.5), forcing a
      floating result even for two INTEGER operands -- matches the
      reference's is_real rule, which treats a bare SLASH as an implicit
      REAL/REAL context even with no floating operand in sight. Promote
      both operands to REAL here; the REAL-arithmetic dispatch branch below
      then does the actual FDiv. This MUST live in the promotion chain, not
      the operator-dispatch chain below -- putting a promotion-only branch
      (one that doesn't itself set `res`) as a terminal arm of that single
      ELSE IF chain would short-circuit past the actual FDiv/FAdd/etc. dispatch
      entirely, leaving `res` unassigned/garbage (found via a real bug this
      way: `int_part * 10.0 + (...)` silently emitted no FAdd at all). It
      must also come first in this chain, before the integer-literal and
      width-promotion arms, or those claim the operands and SLASH reaches
      the integer dispatch unpromoted. }
    lval := IntToFloat(lval, ltk, dblty);
    rval := IntToFloat(rval, rtk, dblty);
    ltk := TK_REAL;
    rtk := TK_REAL;
  END
  ELSE IF (ltk = TK_INTEGER) AND IsIntLiteralLike(left_node) AND IsWideIntTk(rtk) AND
          NOT left_neg_const THEN
  BEGIN
    lval := LLVMConstInt(LLVMTypeForTk(rtk), IntLiteralValue(left_node), 1);
    ltk := rtk;
  END
  ELSE IF (rtk = TK_INTEGER) AND IsIntLiteralLike(right_node) AND IsWideIntTk(ltk) AND
          NOT right_neg_const THEN
  BEGIN
    rval := LLVMConstInt(LLVMTypeForTk(ltk), IntLiteralValue(right_node), 1);
    rtk := ltk;
  END
  ELSE IF IsIntegerFamilyTk(ltk) AND IsIntegerFamilyTk(rtk) AND (ltk <> rtk) AND
          NOT left_neg_const AND ConstantAdaptsToOperand(left_node, right_node, ltk, rtk) THEN
  BEGIN
    { Any other integer constant (MAXINT64, a wide CONST) adapts the same
      way, by the typechecker's ConstantAdaptsToOperand rule. }
    lval := LLVMConstInt(LLVMTypeForTk(rtk), IntLiteralValue(left_node), 1);
    ltk := rtk;
  END
  ELSE IF IsIntegerFamilyTk(ltk) AND IsIntegerFamilyTk(rtk) AND (ltk <> rtk) AND
          NOT right_neg_const AND ConstantAdaptsToOperand(right_node, left_node, rtk, ltk) THEN
  BEGIN
    rval := LLVMConstInt(LLVMTypeForTk(ltk), IntLiteralValue(right_node), 1);
    rtk := ltk;
  END
  ELSE IF ((op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE')) AND
          IsIntegerFamilyTk(ltk) AND IsIntegerFamilyTk(rtk) AND
          (IsUnsignedWordTk(ltk) <> IsUnsignedWordTk(rtk)) THEN
  BEGIN
    { A signed/unsigned relational compares exact values
      (CodegenMixedSignCompare). Extend the narrower operand by its own
      signedness and keep both kinds; the dispatch below reads them. }
    IF IntFamilyWidth(ltk) < IntFamilyWidth(rtk) THEN
    BEGIN
      IF IsUnsignedWordTk(ltk) THEN lval := LLVMBuildZExt(builder, lval, LLVMTypeForTk(rtk), MakeCStr(''))
      ELSE lval := LLVMBuildSExt(builder, lval, LLVMTypeForTk(rtk), MakeCStr(''));
    END
    ELSE IF IntFamilyWidth(rtk) < IntFamilyWidth(ltk) THEN
    BEGIN
      IF IsUnsignedWordTk(rtk) THEN rval := LLVMBuildZExt(builder, rval, LLVMTypeForTk(ltk), MakeCStr(''))
      ELSE rval := LLVMBuildSExt(builder, rval, LLVMTypeForTk(ltk), MakeCStr(''));
    END;
    mixed_sign_cmp := TRUE;
  END
  ELSE IF IsIntegerFamilyTk(ltk) AND IsIntegerFamilyTk(rtk) AND (ltk <> rtk) AND (IntFamilyWidth(ltk) <> IntFamilyWidth(rtk)) THEN
  BEGIN
    { General integer-family width promotion for two non-literal operands
      of different widths (e.g. `start_pos + i` where start_pos is
      INTEGER32 and i is plain INTEGER), matching the reference's
      codegen_binop: extend the narrower operand to the wider width,
      sign-extending unless the narrower side is itself a WORD family
      (unsigned), mirroring _extend_int_for_pascal_expr's signedness rule. }
    IF IntFamilyWidth(ltk) < IntFamilyWidth(rtk) THEN
    BEGIN
      IF IsUnsignedWordTk(ltk) THEN lval := LLVMBuildZExt(builder, lval, LLVMTypeForTk(rtk), MakeCStr(''))
      ELSE lval := LLVMBuildSExt(builder, lval, LLVMTypeForTk(rtk), MakeCStr(''));
      ltk := rtk;
    END
    ELSE
    BEGIN
      IF IsUnsignedWordTk(rtk) THEN rval := LLVMBuildZExt(builder, rval, LLVMTypeForTk(ltk), MakeCStr(''))
      ELSE rval := LLVMBuildSExt(builder, rval, LLVMTypeForTk(ltk), MakeCStr(''));
      rtk := ltk;
    END;
  END
  ELSE IF (ltk = TK_WORD) AND (rtk = TK_INTEGER) THEN
    { Same-width WORD/INTEGER mix widens to INTEGER, matching the
      reference's "WORD mixed with INTEGER -> INTEGER" rule -- no bits
      change (both i16), only the tracked Pascal type does. }
    ltk := TK_INTEGER
  ELSE IF (ltk = TK_INTEGER) AND (rtk = TK_WORD) THEN
    rtk := TK_INTEGER
  ELSE IF (ltk = TK_ADRMEM) AND IsHostDescriptor(rtk) THEN
  BEGIN
    lval := CoerceForAssign(lval, ltk, rtk, left_node, 'pointer comparison'); ltk := rtk;
  END
  ELSE IF (rtk = TK_ADRMEM) AND IsHostDescriptor(ltk) THEN
  BEGIN
    rval := CoerceForAssign(rval, rtk, ltk, right_node, 'pointer comparison'); rtk := ltk;
  END
  ELSE IF (ltk = TK_ADRMEM) AND (TypeKind(rtk) = TK_POINTER) THEN
    { NIL (an ADRMEM constant) against a typed pointer -- both are the
      same opaque i8* value, only the tracked tag differs, the same
      mutual compatibility TypesCompatibleForAssign already applies. }
    ltk := rtk
  ELSE IF (rtk = TK_ADRMEM) AND (TypeKind(ltk) = TK_POINTER) THEN
    rtk := ltk
  ELSE IF IsIntegerFamilyTk(ltk) AND ((rtk = TK_REAL) OR (rtk = TK_REAL32)) THEN
  BEGIN
    { Mixed INTEGER-family/REAL operand: the integer side implicitly
      promotes to the other side's floating width, matching the
      reference's is_real widening (codegen_binop). Same chain-placement
      rationale as the SLASH branch above. }
    lval := IntToFloat(lval, ltk, LLVMTypeForTk(rtk));
    ltk := rtk;
  END
  ELSE IF ((ltk = TK_REAL) OR (ltk = TK_REAL32)) AND IsIntegerFamilyTk(rtk) THEN
  BEGIN
    rval := IntToFloat(rval, rtk, LLVMTypeForTk(ltk));
    rtk := ltk;
  END
  ELSE IF (ltk = TK_REAL32) AND (rtk = TK_REAL) THEN
  BEGIN
    lval := LLVMBuildFPExt(builder, lval, dblty, MakeCStr(''));
    ltk := TK_REAL;
  END
  ELSE IF (ltk = TK_REAL) AND (rtk = TK_REAL32) THEN
  BEGIN
    rval := LLVMBuildFPExt(builder, rval, dblty, MakeCStr(''));
    rtk := TK_REAL;
  END;

  { A single flat ELSE IF chain, deliberately avoiding a bare EXIT
    statement: this dialect has no EXIT statement/procedure at all (verified
    against the Python reference -- any EXIT reference fails to parse as a
    procedure call with "Undefined procedure: EXIT"), so early-return from
    deep inside nested IFs isn't expressible here regardless. A single
    terminal assignment is the only option. }
  IF IsHostDescriptor(ltk) OR IsHostDescriptor(rtk) THEN
  BEGIN
    IF ltk <> rtk THEN AbortWith('codegen: incompatible super-array descriptor pointer comparison');
    IF (op <> 'EQ') AND (op <> 'NEQ') THEN
      AbortWith('codegen: super-array descriptor pointer arithmetic/ordering is unsupported');
    lval := LLVMBuildExtractValue(builder, lval, 0, MakeCStr(''));
    rval := LLVMBuildExtractValue(builder, rval, 0, MakeCStr(''));
    IF op = 'EQ' THEN res := LLVMBuildICmp(builder, LLVMIntEQ, lval, rval, MakeCStr(''))
    ELSE res := LLVMBuildICmp(builder, LLVMIntNE, lval, rval, MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF (TypeKind(ltk) = TK_VECTOR) OR (TypeKind(rtk) = TK_VECTOR) THEN
  BEGIN
    { Elementwise arithmetic/logic, or a lanewise comparison. Both operands
      must be the identical VECTOR type -- the callee emits the mixed-type
      error otherwise (a scalar operand also lands here since its tk is not
      TK_VECTOR). A comparison yields a VECTOR [n] OF BOOLEAN mask. }
    IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE') THEN
    BEGIN
      res := CodegenVectorCmp(op, lval, rval, ltk, rtk);
      IF TypeKind(ltk) = TK_VECTOR THEN
        last_val_tk := EnsureBoolVectorType(types[ltk].hi - types[ltk].lo + 1)
      ELSE
        last_val_tk := EnsureBoolVectorType(types[rtk].hi - types[rtk].lo + 1);
    END
    ELSE IF (ltk = rtk) AND IsIntegerFamilyTk(types[ltk].elem_tid) AND
            (((op = 'DIV') OR (op = 'MOD')) OR
             (((op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL')) AND SiteMathCk(site))) THEN
    BEGIN
      { Integer lanes: checked + - * under MATHCK+, and DIV/MOD always,
        since a vector udiv/sdiv by a zero lane (or signed MIN/-1) is LLVM
        undefined behavior. MATHCK- + - * keep the wrapping vector form. }
      res := CodegenLanewiseIntOp(op, lval, rval, ltk, site);
      last_val_tk := ltk;
    END
    ELSE
    BEGIN
      res := CodegenVectorBinOp(op, lval, rval, ltk, rtk);
      last_val_tk := ltk;
    END;
  END
  ELSE IF (op = 'AND') OR (op = 'OR') THEN
  BEGIN
    IF (ltk <> TK_BOOLEAN) OR (rtk <> TK_BOOLEAN) THEN
      AbortWith('codegen: AND/OR require BOOLEAN operands');
    IF op = 'AND' THEN res := LLVMBuildAnd(builder, lval, rval, MakeCStr(''))
    ELSE res := LLVMBuildOr(builder, lval, rval, MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF op = 'IN' THEN
  BEGIN
    { Zero-extend so a BOOLEAN TRUE (i1) is ordinal 1, not -1. }
    IF (ltk = TK_CHAR) OR (ltk = TK_BOOLEAN) THEN
      lval := LLVMBuildZExt(builder, lval, i16ty, MakeCStr(''))
    ELSE IF TypeKind(ltk) = TK_ENUM THEN
      lval := LLVMBuildTrunc(builder, lval, i16ty, MakeCStr(''))
    ELSE IF ltk <> TK_INTEGER THEN
      AbortWith('codegen: IN requires an INTEGER, CHAR, BOOLEAN or enum left operand');
    IF TypeKind(rtk) <> TK_SET THEN
      AbortWith('codegen: IN requires a SET right operand');
    { A declared SET exposes its representation base. Anonymous sets carry
      only a generic tid; their semantic host was checked before codegen. }
    IF rtk <> generic_set_tid THEN
      IF types[rtk].elem_tid <> SubrangeBaseTid(ltk) THEN
        AbortWith('codegen: incompatible declared SET base in IN');
    res := CodegenSetMember(lval, rval);
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF (TypeKind(ltk) = TK_SET) AND (TypeKind(rtk) = TK_SET) THEN
  BEGIN
    { Both values have already been evaluated once, left then right. No
      operand is revisited to check the representable declared bases. }
    IF DeclaredSetBasesConflict(ltk, rtk) THEN
      AbortWith('codegen: incompatible declared SET bases');
    res := CodegenSetBinOp(op, lval, rval);
  END
  ELSE IF (op = 'PLUS') AND ((ltk = TK_ADRMEM) OR (TypeKind(ltk) = TK_POINTER)) AND IsIntegerFamilyTk(rtk) THEN
  BEGIN
    { ADRMEM and ^CHAR are byte-addressed, but a general POINTER must use
      its declared pointee type as LLVM's GEP source element type. In
      particular, ^ADRMEM is a pointer-slot array, not a byte array. }
    IF ltk = TK_ADRMEM THEN ptr_elem_ty := i8ty
    ELSE ptr_elem_ty := LLVMTypeForTk(types[ltk].elem_tid);
    { GEP reads its index as signed at the index's own width, so widen it
      by the offset's own signedness first: a WORD offset of 40000 is
      40000 elements, not -25536. Address arithmetic is not MATHCK; the
      non-inbounds GEP wraps without LLVM undefined behavior. A literal
      offset was built as a 16-bit INTEGER (40000 as -25536), so rebuild it
      from its exact value. }
    gep_idx := AllocPtrArray(1);
    IF IsIntLiteralLike(right_node) THEN
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i64ty, IntLiteralValue(right_node), 1))
    ELSE
      SetPtrArrayElem(gep_idx, 0, MathReportOperand(rval, rtk));
    res := LLVMBuildGEP2(builder, ptr_elem_ty, lval, gep_idx, 1, MakeCStr(''));
    last_val_tk := ltk;
  END
  ELSE IF (op = 'PLUS') AND ((rtk = TK_ADRMEM) OR (TypeKind(rtk) = TK_POINTER)) AND IsIntegerFamilyTk(ltk) THEN
  BEGIN
    IF rtk = TK_ADRMEM THEN ptr_elem_ty := i8ty
    ELSE ptr_elem_ty := LLVMTypeForTk(types[rtk].elem_tid);
    gep_idx := AllocPtrArray(1);
    IF IsIntLiteralLike(left_node) THEN
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i64ty, IntLiteralValue(left_node), 1))
    ELSE
      SetPtrArrayElem(gep_idx, 0, MathReportOperand(lval, ltk));
    res := LLVMBuildGEP2(builder, ptr_elem_ty, rval, gep_idx, 1, MakeCStr(''));
    last_val_tk := rtk;
  END
  ELSE IF mixed_sign_cmp THEN
  BEGIN
    IF IntFamilyWidth(ltk) >= IntFamilyWidth(rtk) THEN
      res := CodegenMixedSignCompare(op, lval, rval, IsUnsignedWordTk(ltk), ltk)
    ELSE
      res := CodegenMixedSignCompare(op, lval, rval, IsUnsignedWordTk(ltk), rtk);
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF ltk <> rtk THEN
  BEGIN
    AbortWith('codegen: mixed-type operands are not supported (no implicit promotion)');
    res := NIL;
  END
  ELSE IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE') THEN
  BEGIN
    { Use the adapted/promoted operand type, not the destination type, to
      select signedness. Equality is independent of signedness; WORD-family
      ordering must treat the high bit as data, not a sign bit. }
    IF (ltk = TK_INTEGER) OR (ltk = TK_WORD) OR (ltk = TK_INTEGER8) OR (ltk = TK_WORD8) OR
       (ltk = TK_INTEGER32) OR (ltk = TK_WORD32) OR (ltk = TK_INTEGER64) OR (ltk = TK_WORD64) OR
       (ltk = TK_CHAR) OR (ltk = TK_BOOLEAN) OR (TypeKind(ltk) = TK_ENUM) THEN
    BEGIN
      { CHAR/BOOLEAN are ordinal in Pascal, so full ordering (not just EQ/
        NEQ) is meaningful for them too, and LLVM's icmp works the same way
        on their i8/i1 representations as on the integer widths above. }
      IF op = 'EQ' THEN res := LLVMBuildICmp(builder, LLVMIntEQ, lval, rval, MakeCStr(''))
      ELSE IF op = 'NEQ' THEN res := LLVMBuildICmp(builder, LLVMIntNE, lval, rval, MakeCStr(''))
      ELSE IF IsUnsignedWordTk(ltk) THEN
      BEGIN
        IF op = 'LT' THEN res := LLVMBuildICmp(builder, LLVMIntULT, lval, rval, MakeCStr(''))
        ELSE IF op = 'LE' THEN res := LLVMBuildICmp(builder, LLVMIntULE, lval, rval, MakeCStr(''))
        ELSE IF op = 'GT' THEN res := LLVMBuildICmp(builder, LLVMIntUGT, lval, rval, MakeCStr(''))
        ELSE res := LLVMBuildICmp(builder, LLVMIntUGE, lval, rval, MakeCStr(''));
      END
      ELSE IF op = 'LT' THEN res := LLVMBuildICmp(builder, LLVMIntSLT, lval, rval, MakeCStr(''))
      ELSE IF op = 'LE' THEN res := LLVMBuildICmp(builder, LLVMIntSLE, lval, rval, MakeCStr(''))
      ELSE IF op = 'GT' THEN res := LLVMBuildICmp(builder, LLVMIntSGT, lval, rval, MakeCStr(''))
      ELSE res := LLVMBuildICmp(builder, LLVMIntSGE, lval, rval, MakeCStr(''));
    END
    ELSE IF (ltk = TK_ADRMEM) OR (TypeKind(ltk) = TK_POINTER) THEN
    BEGIN
      { Only equality is meaningful for a pointer/opaque handle (NIL checks,
        pervasive in the other native sources) -- LLVM's icmp still needs an
        integer predicate even for a pointer-typed operand. }
      IF op = 'EQ' THEN res := LLVMBuildICmp(builder, LLVMIntEQ, lval, rval, MakeCStr(''))
      ELSE IF op = 'NEQ' THEN res := LLVMBuildICmp(builder, LLVMIntNE, lval, rval, MakeCStr(''))
      ELSE
      BEGIN
        AbortWith('codegen: only = and <> are supported for pointer/ADRMEM operands');
        res := NIL;
      END;
    END
    ELSE IF (ltk = TK_REAL) OR (ltk = TK_REAL32) THEN
    BEGIN
      IF op = 'EQ' THEN res := LLVMBuildFCmp(builder, LLVMRealOEQ, lval, rval, MakeCStr(''))
      ELSE IF op = 'NEQ' THEN res := LLVMBuildFCmp(builder, LLVMRealONE, lval, rval, MakeCStr(''))
      ELSE IF op = 'LT' THEN res := LLVMBuildFCmp(builder, LLVMRealOLT, lval, rval, MakeCStr(''))
      ELSE IF op = 'LE' THEN res := LLVMBuildFCmp(builder, LLVMRealOLE, lval, rval, MakeCStr(''))
      ELSE IF op = 'GT' THEN res := LLVMBuildFCmp(builder, LLVMRealOGT, lval, rval, MakeCStr(''))
      ELSE res := LLVMBuildFCmp(builder, LLVMRealOGE, lval, rval, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith('codegen: relational operators support only INTEGER/REAL operands');
      res := NIL;
    END;
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF (ltk = TK_INTEGER) OR (ltk = TK_WORD) OR (ltk = TK_INTEGER8) OR (ltk = TK_WORD8) OR
          (ltk = TK_INTEGER32) OR (ltk = TK_WORD32) OR (ltk = TK_INTEGER64) OR (ltk = TK_WORD64) THEN
  BEGIN
    { Wrapping add/sub/mul have the same bit result for both families.
      DIV/MOD use the adapted/promoted operand type's signedness and
      mandatory safe lowering, including for legacy unchecked ASTs. }
    { NVPTX has no host failure path: an operation MATHCK+ would check is
      an unsupported boundary there (MathckDeviceBoundary). A fully constant
      operation is not checked here: the typechecker range-checks its exact
      folded value against the target, and consumers such as CoerceForAssign
      rebuild it from the AST at the target width (Base + Step into
      INTEGER32 is 33000, though the INTEGER operands would overflow). }
    IF is_nvptx_device AND SiteMathCk(site) AND NOT TcFoldedOperation(site) AND
       ((op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') OR (op = 'DIV') OR (op = 'MOD')) THEN
      MathckDeviceBoundary(site);
    IF ((op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL')) AND SiteMathCk(site) AND
       NOT is_nvptx_device AND NOT TcFoldedOperation(site) THEN
      res := CodegenCheckedArith(op, lval, rval, ltk, site)
    ELSE IF op = 'PLUS' THEN res := LLVMBuildAdd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MINUS' THEN res := LLVMBuildSub(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MUL' THEN res := LLVMBuildMul(builder, lval, rval, MakeCStr(''))
    ELSE IF (op = 'DIV') OR (op = 'MOD') THEN
      res := CodegenSafeDivMod(op, lval, rval, ltk, site)
    ELSE
    BEGIN
      AbortWith2('codegen: unhandled integer-family operator: ', op);
      res := NIL;
    END;
    last_val_tk := ltk;
  END
  ELSE IF (ltk = TK_REAL) OR (ltk = TK_REAL32) THEN
  BEGIN
    IF op = 'PLUS' THEN res := LLVMBuildFAdd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MINUS' THEN res := LLVMBuildFSub(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MUL' THEN res := LLVMBuildFMul(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'SLASH' THEN res := LLVMBuildFDiv(builder, lval, rval, MakeCStr(''))
    ELSE
    BEGIN
      AbortWith2('codegen: unhandled REAL/REAL32 operator: ', op);
      res := NIL;
    END;
    last_val_tk := ltk;
  END
  ELSE
  BEGIN
    AbortWith('codegen: arithmetic operators support only INTEGER/REAL operands');
    res := NIL;
  END;
  END;
  END;
  CodegenBinOp := res;
END;

FUNCTION CodegenUnaryOp(op: Str255; operand_node, site: ADRMEM): ADRMEM;
{ site is the UnaryOp node itself: per-operation metadata is read from it. }
VAR
  v, res: ADRMEM;
  tk: INTEGER;
BEGIN
  v := CodegenExpr(operand_node);
  tk := FoldedOperationTk(site);
  IF tk <> TK_UNKNOWN THEN
  BEGIN
    { Same as CodegenBinOp: the exact checked constant. }
    last_val_tk := tk;
    CodegenUnaryOp := LLVMConstInt(LLVMTypeForTk(tk), IntLiteralValue(site), 1);
    RETURN;
  END;
  tk := last_val_tk;
  IF TypeKind(tk) = TK_VECTOR THEN
  BEGIN
    IF (op = 'MINUS') AND IsIntegerFamilyTk(types[tk].elem_tid) AND SiteMathCk(site) THEN
      res := CodegenLanewiseIntOp('NEG', v, NIL, tk, site)
    ELSE
      res := CodegenVectorUnaryOp(op, v, tk);
    last_val_tk := tk;
    CodegenUnaryOp := res;
    RETURN;
  END;
  IF op = 'MINUS' THEN
  BEGIN
    { Same exemptions as checked + - *: legacy/MATHCK- nodes wrap, DEVICE
      code is not checked yet, and a fully constant negation such as
      -32768 is folded and range-checked by the typechecker. }
    IF IsIntegerFamilyTk(tk) AND SiteMathCk(site) AND is_nvptx_device AND
       NOT TcFoldedOperation(site) THEN
      MathckDeviceBoundary(site);
    IF IsIntegerFamilyTk(tk) AND SiteMathCk(site) AND NOT is_nvptx_device AND
       NOT TcFoldedOperation(site) THEN
      res := CodegenCheckedNegate(v, tk, site)
    ELSE IF (tk = TK_INTEGER) OR (tk = TK_WORD) THEN res := LLVMBuildSub(builder, LLVMConstInt(i16ty, 0, 1), v, MakeCStr(''))
    ELSE IF (tk = TK_INTEGER8) OR (tk = TK_WORD8) THEN res := LLVMBuildSub(builder, LLVMConstInt(i8ty, 0, 1), v, MakeCStr(''))
    ELSE IF (tk = TK_INTEGER32) OR (tk = TK_WORD32) THEN res := LLVMBuildSub(builder, LLVMConstInt(i32ty, 0, 1), v, MakeCStr(''))
    ELSE IF (tk = TK_INTEGER64) OR (tk = TK_WORD64) THEN res := LLVMBuildSub(builder, LLVMConstInt(i64ty, 0, 1), v, MakeCStr(''))
    ELSE IF tk = TK_REAL THEN res := LLVMBuildFSub(builder, LLVMConstReal(dblty, 0.0), v, MakeCStr(''))
    ELSE IF tk = TK_REAL32 THEN res := LLVMBuildFSub(builder, LLVMConstReal(f32ty, 0.0), v, MakeCStr(''))
    ELSE
    BEGIN
      AbortWith('codegen: unary MINUS requires an integer-family or REAL/REAL32 operand');
      res := NIL;
    END;
    last_val_tk := tk;
  END
  ELSE IF op = 'NOT' THEN
  BEGIN
    IF tk <> TK_BOOLEAN THEN
      AbortWith('codegen: NOT requires a BOOLEAN operand');
    res := LLVMBuildXor(builder, v, LLVMConstInt(i1ty, 1, 0), MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unhandled unary operator: ', op);
    res := NIL;
  END;
  CodegenUnaryOp := res;
END;


FUNCTION ShadowedWriteArg(arg: ADRMEM; name: Str255): ADRMEM;
{ ps_stmt.pas wraps the actual arguments of anything spelled WRITE/WRITELN in
  WriteArg nodes, case-insensitively and without consulting any declaration.
  A call to a user-declared WRITELN therefore reaches this generic path
  wrapped, and CodegenExpr has no WriteArg case. Mirrors tc_stmt.pas's own
  ShadowedWriteArg, including its rejection of a `:width:precision' suffix --
  which the typechecker reports first, this being the belt-and-braces half
  for a stage driven directly. }
BEGIN
  IF NodeType(arg) = 'WriteArg' THEN
  BEGIN
    IF (GetObjOrNil(arg, 'width') <> NIL) OR (GetObjOrNil(arg, 'precision') <> NIL) THEN
      AbortWith2('codegen: field width specifier is not allowed in a call to the user-declared ', name);
    ShadowedWriteArg := GetObj(arg, 'expr');
  END
  ELSE
    ShadowedWriteArg := arg;
END;

FUNCTION CodegenCallCommon(name: Str255; args_arr: ADRMEM): ADRMEM;
{ Shared by a FuncCall expression and a bare ProcCallStmt that isn't
  WRITE/WRITELN: look up a user-declared routine, marshal its arguments
  (VAR-mode: the callee needs the callee's storage address directly, so the
  actual argument must be a bare Identifier and is passed unloaded; value
  mode: CodegenExpr as usual), and build the call. Sets last_val_tk to the
  routine's return type kind (TK_UNKNOWN for a PROCEDURE, meaningless to
  the caller in that case). }
VAR
  ri: INTEGER32;
  nargs, i: INTEGER32;
  call_args: ADRMEM;
  arg_node, v, v_tmp: ADRMEM;
  arg_nm: Str255;
  symi: INTEGER32;
  arg_routi: INTEGER32;
  is_bare_niladic_call: BOOLEAN;
  res: ADRMEM;
  bv_temp, byval_attr, align_attr: ADRMEM;
  llvm_ai: INTEGER32;
  pieces_emitted: BOOLEAN;
  agg_class, n_pieces, eb: INTEGER;
  piece_kind: SysVPieceArr;
  piece_bytes: SysVPieceSzArr;
  cstruct_ty, cptr, piece_ptr, piece_val: ADRMEM;
  ret_class, ret_npieces: INTEGER;
  ret_pk: SysVPieceArr;
  ret_pb: SysVPieceSzArr;
  sret_slot, sret_attr, noalias_attr, ret_ll, ret_cptr: ADRMEM;
  arg_state: ARRAY [1..MAX_PARAMS] OF ADRMEM; { INITCK state temps of
    tracked value actuals, published just before the call }
  transports, track_arg, track_ret, track_agg, agg_taint: BOOLEAN;
  saved_taint, agg_shadow, saved_source, var_shadow: ADRMEM;
  publishes: BOOLEAN;
  ack, acked, returned: ADRMEM;
  ptr_actual: ARRAY [1..MAX_PARAMS] OF ADRMEM; { data addresses a plain
    EXTERN receives (typed pointer values, the element data of descriptors
    passed by value or bound by VAR/CONST), whose referents C may write }
  call_base: INTEGER32; { initck_npending before this call's actuals }
  outer_taint: ADRMEM;
BEGIN
  ri := LookupRoutine(name);
  IF ri = 0 THEN
  BEGIN
    AbortWith2('codegen: undefined procedure/function: ', name);
    res := NIL;
  END
  ELSE
  BEGIN
    nargs := ArrSize(args_arr);
    { A [VARARGS] routine's nparams counts only the fixed prefix, so extra
      trailing arguments are legal there (and only there). }
    IF (nargs <> routines[ri].nparams)
       AND NOT (routines[ri].is_vararg AND (nargs > routines[ri].nparams)) THEN
      AbortWith2('codegen: argument count mismatch calling: ', name);
    { A COERCED-class [C] aggregate argument expands into one LLVM argument
      per eightbyte (at most two), so the LLVM argument list can be longer
      than the Pascal one and its index has to be tracked separately -- see
      llvm_ai below. Two slots per Pascal argument is the worst case, plus
      one for the hidden sret result pointer a MEMORY-class aggregate return
      prepends -- which is also why the array is sized nargs * 2 + 1 rather
      than nargs * 2 (an sret call with no real arguments at all still needs
      one slot). }
    IF is_nvptx_device THEN ret_class := 0
    ELSE
    BEGIN
      ret_class := FuncRetAggClass(ri);
      IF ret_class <> 0 THEN
        ClassifyAggregate(routines[ri].ret_tk, ret_class, ret_npieces, ret_pk, ret_pb);
    END;
    call_args := AllocPtrArray(nargs * 2 + 1);
    transports := InitckTransports(ri);
    FOR i := 1 TO MAX_PARAMS DO arg_state[i] := NIL;
    FOR i := 1 TO MAX_PARAMS DO ptr_actual[i] := NIL;
    llvm_ai := 0;
    IF ret_class = SYSV_CLASS_MEMORY THEN
    BEGIN
      { The callee writes its result through this pointer and returns void;
        the aggregate is loaded back out of it below so this function's
        contract -- "returns the call's result as an SSA value" -- is
        unchanged for every caller. }
      sret_slot := EntryAlloca(LLVMTypeForTk(routines[ri].ret_tk), '');
      SetPtrArrayElem(call_args, 0, sret_slot);
      llvm_ai := 1;
    END;
    { Unmodeled effects of the call its actuals mention are queued and take
      place just before the call (InitckReleaseAtCall). }
    call_base := initck_npending;
    initck_call_depth := initck_call_depth + 1;
    FOR i := 0 TO nargs - 1 DO
    BEGIN
      pieces_emitted := FALSE;
      { Each actual is evaluated in its own accumulator: its unchecked reads
        reach the callee only as the state it is handed (a transported
        actual), never the caller's value, whose state comes from the result. }
      outer_taint := initck_taint;
      initck_taint := NIL;
      arg_node := ShadowedWriteArg(ArrItem(args_arr, i), name);
      IF i >= routines[ri].nparams THEN
      BEGIN
        { Variadic tail argument: there is no formal parameter at all, so
          none of the param_is_var/param_needs_copy machinery applies (those
          arrays only have nparams valid entries). Evaluate the argument and
          apply C's default argument promotions, exactly as the reference's
          codegen_c_abi_call does for the same tail. }
        v := CodegenExpr(arg_node);
        IF InitckPointerTk(last_val_tk) AND NOT is_device_compiland THEN
          InitckReleaseAtCall(v, 0);
        v := VariadicPromote(v, last_val_tk, name);
      END
      ELSE IF routines[ri].param_is_var[i + 1] THEN
      BEGIN
        var_shadow := NIL;
        IF NodeType(arg_node) = 'Identifier' THEN
        BEGIN
          arg_nm := GetStr(arg_node, 'name');
          symi := LookupSym(arg_nm);
          arg_routi := LookupRoutine(arg_nm);
          is_bare_niladic_call := (symi = 0) AND RoutineIsFunc(arg_routi);
          IF is_bare_niladic_call THEN
          BEGIN
            { A bare niladic-call Identifier (e.g. `StringEqual(CurKind,
              target_k)`, an aggregate Str255-returning FUNCTION called
              without parens) has no symbol-table entry of its own --
              materialize the call's result into a fresh temporary and
              pass that temporary's address, same as ComputeDesignatorAddress
              does for the same shape reached via a Designator. }
            IF (IsHostDescriptor(routines[arg_routi].ret_tk) OR IsHostDescriptor(routines[ri].param_tk[i + 1])) AND
               (routines[arg_routi].ret_tk <> routines[ri].param_tk[i + 1]) THEN
              AbortWith('codegen: incompatible super-array descriptor VAR result argument');
            v := EntryAlloca(LLVMTypeForTk(routines[arg_routi].ret_tk), '');
            LLVMBuildStore(builder, CodegenCallCommon(arg_nm, NIL), v);
          END
          ELSE
          BEGIN
            IF symi = 0 THEN
              AbortWith2('codegen: undefined variable: ', arg_nm);
            { Structurally-identical equal-capacity string types interoperate,
              matching the reference -- see AggStringTypesInterchangeable. }
            IF (symbols[symi].tk <> routines[ri].param_tk[i + 1])
               AND NOT AggStringTypesInterchangeable(symbols[symi].tk,
                         routines[ri].param_tk[i + 1]) THEN
              AbortWith2('codegen: VAR argument type mismatch calling: ', name);
            v := symbols[symi].llvm_val;
            IF InitckTracked(symi) THEN var_shadow := symbols[symi].init_state;
          END;
        END
        ELSE IF NodeType(arg_node) = 'Designator' THEN
        BEGIN
          v := ComputeDesignatorAddress(arg_node);
          var_shadow := last_desig_shadow;
          { See AggStringTypesInterchangeable -- equal-capacity string types. }
          IF (last_val_tk <> routines[ri].param_tk[i + 1])
             AND NOT AggStringTypesInterchangeable(last_val_tk,
                       routines[ri].param_tk[i + 1]) THEN
            AbortWith2('codegen: VAR argument type mismatch calling: ', name);
        END
        ELSE
        BEGIN
          AbortWith2('codegen: a VAR argument must be an lvalue, calling: ', name);
          v := NIL;
        END;
        { A tracked VAR/CONST formal shares the actual's own state when the
          actual is tracked storage: a direct slot or formal, a forwarded
          VAR binding, a selected leaf, or a whole or sub-aggregate. Otherwise
          nothing is published and the callee binds private initialized
          state. Binding is not a read. }
        IF transports AND (var_shadow <> NIL) THEN
          IF InitckShadowSize(routines[ri].param_tk[i + 1]) > 0 THEN
            arg_state[i + 1] := var_shadow;
        { A [C] routine may write any leaf of the storage bound to its
          VAR/CONST formal, and nothing tells us which: exactly that extent
          becomes initialized at the call, never its siblings or other
          storage. Binding is not a read. }
        IF routines[ri].is_c AND (var_shadow <> NIL) AND (NOT is_device_compiland) THEN
          IF InitckShadowSize(routines[ri].param_tk[i + 1]) > 0 THEN
            InitckReleaseAtCall(var_shadow, routines[ri].param_tk[i + 1]);
        IF transports AND routines[ri].is_extern AND
           IsHostDescriptor(routines[ri].param_tk[i + 1]) THEN
          ptr_actual[i + 1] := InitckDescriptorData(v, routines[ri].param_tk[i + 1]);
      END
      ELSE IF routines[ri].param_needs_copy[i + 1] THEN
      BEGIN
        IF is_nvptx_device THEN
        BEGIN
          { Device value aggregates travel as one LLVM aggregate value. }
          v := CodegenExpr(arg_node);
          v := CoerceForAssign(v, last_val_tk, routines[ri].param_tk[i + 1], arg_node, name);
        END
        ELSE
        BEGIN
          { A tracked aggregate actual is a whole-value read: checked before
            its bytes are copied, or (unchecked) a snapshot of its leaf
            states travels to a transporting callee. }
          track_agg := InitckShadowSize(routines[ri].param_tk[i + 1]) > 0;
          agg_shadow := NIL;
          IF track_agg THEN
          BEGIN
            saved_taint := BeginInitckValue(arg_node);
            agg_taint := initck_taint <> NIL;
            saved_source := initck_copy_source;
            initck_copy_source := arg_node;
          END;
          { Value-mode aggregate param, plain Pascal and [C] FOREIGN alike:
          SysV MEMORY-class byval -- compute the source's address, then
          ALWAYS copy it into a fresh per-call temp via EmitBlockCopy and
          pass that temp's address. Never pass caller storage raw: even
          though nothing else could presently alias e.g. a StringLiteral's
          own already-fresh temp, doing this unconditionally keeps one
          predictable shape matching c_abi.py's caller-side marshalling,
          and is what makes byval's callee-private-copy guarantee actually
          hold for the Identifier/Designator cases that DO name
          caller-owned storage. The byval(ty)/align call-site attributes
          are attached after LLVMBuildCall2 below. }
        IF NodeType(arg_node) = 'Identifier' THEN
        BEGIN
          arg_nm := GetStr(arg_node, 'name');
          symi := LookupSym(arg_nm);
          arg_routi := LookupRoutine(arg_nm);
          is_bare_niladic_call := (symi = 0) AND RoutineIsFunc(arg_routi);
          IF is_bare_niladic_call THEN
          BEGIN
            IF (IsHostDescriptor(routines[arg_routi].ret_tk) OR IsHostDescriptor(routines[ri].param_tk[i + 1])) AND
               (routines[arg_routi].ret_tk <> routines[ri].param_tk[i + 1]) THEN
              AbortWith('codegen: incompatible super-array descriptor value result argument');
            v := EntryAlloca(LLVMTypeForTk(routines[arg_routi].ret_tk), '');
            LLVMBuildStore(builder, CodegenCallCommon(arg_nm, NIL), v);
          END
          ELSE
          BEGIN
            IF symi = 0 THEN
              AbortWith2('codegen: undefined variable: ', arg_nm);
            { See AggStringTypesInterchangeable -- equal-capacity string types. }
            IF (symbols[symi].tk <> routines[ri].param_tk[i + 1])
               AND NOT AggStringTypesInterchangeable(symbols[symi].tk,
                         routines[ri].param_tk[i + 1]) THEN
              AbortWith2('codegen: value-aggregate argument type mismatch calling: ', name);
            v := symbols[symi].llvm_val;
            IF track_agg AND InitckTracked(symi) THEN
            BEGIN
              agg_shadow := symbols[symi].init_state;
              GuardInitckRead(arg_node, symi);
            END;
          END;
        END
        ELSE IF NodeType(arg_node) = 'Designator' THEN
        BEGIN
          v := ComputeDesignatorAddress(arg_node);
          IF track_agg AND (last_desig_shadow <> NIL) THEN
          BEGIN
            agg_shadow := last_desig_shadow;
            GuardInitckComponent(arg_node, agg_shadow, routines[ri].param_tk[i + 1]);
          END;
          { See AggStringTypesInterchangeable -- equal-capacity string types. }
          IF (last_val_tk <> routines[ri].param_tk[i + 1])
             AND NOT AggStringTypesInterchangeable(last_val_tk,
                       routines[ri].param_tk[i + 1]) THEN
            AbortWith2('codegen: value-aggregate argument type mismatch calling: ', name);
        END
        ELSE IF (NodeType(arg_node) = 'StringLiteral')
            AND ((TypeKind(routines[ri].param_tk[i + 1]) = TK_LSTRING) OR (TypeKind(routines[ri].param_tk[i + 1]) = TK_STRING)) THEN
        BEGIN
          v := EntryAlloca(LLVMTypeForTk(routines[ri].param_tk[i + 1]), '');
          IF TypeKind(routines[ri].param_tk[i + 1]) = TK_LSTRING THEN
            CodegenLStringLiteralAssign(v, routines[ri].param_tk[i + 1], DecodeStringLiteral(GetStr(arg_node, 'value')))
          ELSE
            CodegenStringLiteralAssign(v, routines[ri].param_tk[i + 1], DecodeStringLiteral(GetStr(arg_node, 'value')));
        END
        ELSE IF NodeType(arg_node) = 'FuncCall' THEN
        BEGIN
          v := EntryAlloca(LLVMTypeForTk(routines[ri].param_tk[i + 1]), '');
          v_tmp := CodegenExpr(arg_node);
          v_tmp := CoerceForAssign(v_tmp, last_val_tk, routines[ri].param_tk[i + 1], arg_node, name);
          LLVMBuildStore(builder, v_tmp, v);
        END
        ELSE
        BEGIN
          { Any other value-mode aggregate-shaped expression: CodegenExpr
            produces it as an SSA value, so materialize it into a fresh temp
            to get an address to classify/copy from. }
          v_tmp := CodegenExpr(arg_node);
          v_tmp := CoerceForAssign(v_tmp, last_val_tk, routines[ri].param_tk[i + 1], arg_node, name);
          v := EntryAlloca(LLVMTypeForTk(routines[ri].param_tk[i + 1]), '');
          LLVMBuildStore(builder, v_tmp, v);
        END;
        IF transports AND routines[ri].is_extern AND
           IsHostDescriptor(routines[ri].param_tk[i + 1]) THEN
          ptr_actual[i + 1] := InitckDescriptorData(v, routines[ri].param_tk[i + 1]);
        IF track_agg THEN
        BEGIN
          initck_copy_source := saved_source;
          IF transports AND ((agg_shadow <> NIL) OR agg_taint) THEN
          BEGIN
            arg_state[i + 1] := EntryAlloca(InitckShadowTy(routines[ri].param_tk[i + 1]),
                                            'initck.actual');
            InitckTransferShadow(arg_state[i + 1], agg_shadow,
                                 routines[ri].param_tk[i + 1], EndInitckValue(saved_taint));
          END
          ELSE initck_taint := saved_taint;
        END;
        ClassifyParamAt(routines[ri].param_tk, routines[ri].param_is_var,
                        routines[ri].param_needs_copy, i + 1, ret_class = SYSV_CLASS_MEMORY,
                        agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
        BEGIN
          bv_temp := EntryAlloca(LLVMTypeForTk(routines[ri].param_tk[i + 1]), '');
          { The call-site byval attribute below promises SysVByvalAlign(...)
            (min 8) to the callee. LLVM's default alloca alignment for the
            aggregate's IR type is not guaranteed to meet that -- force it
            explicitly, matching every other slot whose alignment a byval/
            sret attribute makes a promise about (sret_temp, cur_func_ret_slot,
            the COERCED prologue palloca). Leaving this unset lets the
            backend trust the attribute's alignment for wide/vectorized
            copies against memory that isn't actually that aligned. }
          LLVMSetAlignment(bv_temp, SysVByvalAlign(routines[ri].param_tk[i + 1]));
          EmitBlockCopy(bv_temp, v, TypeSizeBytes(routines[ri].param_tk[i + 1]));
          v := bv_temp;
        END
        ELSE
        BEGIN
          { COERCED class: the aggregate travels in one or two registers
            instead of memory, so there is nothing for the callee to alias
            and no private copy to make. View the source storage as the
            coerced piece struct and pass each eightbyte as its own LLVM
            argument, mirroring c_abi.py's coerced call-site marshalling.
            Each load carries the AGGREGATE's alignment, not the piece
            type's: an eightbyte read out of e.g. a 4-aligned two-INTEGER32
            record is an i64 load of align 4, exactly as clang emits it. }
          cstruct_ty := SysVCoercedStructType(n_pieces, piece_kind, piece_bytes);
          cptr := LLVMBuildBitCast(builder, v, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
          FOR eb := 1 TO n_pieces DO
          BEGIN
            piece_ptr := SysVCoercedPiecePtr(cptr, cstruct_ty, eb);
            piece_val := LLVMBuildLoad2(builder, SysVPieceLLVMType(piece_kind[eb], piece_bytes[eb]),
                                        piece_ptr, MakeCStr(''));
            LLVMSetAlignment(piece_val, TypeAlignBytes(routines[ri].param_tk[i + 1]));
            SetPtrArrayElem(call_args, llvm_ai, piece_val);
            llvm_ai := llvm_ai + 1;
          END;
          pieces_emitted := TRUE;
        END;
        END;
      END
      ELSE
      BEGIN
        { A tracked value formal receives the evaluated actual's state:
          collected like an assignment RHS, so an unchecked unset source
          reaches the callee unset rather than blessed by the copy. }
        track_arg := transports;
        IF track_arg THEN track_arg := InitckTrackedTk(routines[ri].param_tk[i + 1]);
        IF track_arg THEN saved_taint := BeginInitckValue(arg_node);
        v := CodegenExpr(arg_node);
        { Value-mode call arguments get the same literal-adaptation leniency
          as an assignment RHS (e.g. a bare INTEGER literal passed to a CINT
          [C] EXTERN parameter, as with cJSON_CreateBool(1) or exit(1)):
          reuse CoerceForAssign rather than a bare tid-equality check. A
          subrange parameter is range-checked like an assignment. }
        initck_defer_conv := TRUE;
        v := CoerceCheckedForAssign(v, last_val_tk, routines[ri].param_tk[i + 1], arg_node, name);
        initck_defer_conv := FALSE;
        { A pointer handed to a [C] routine exposes its referent to writes
          whose state is not modeled. }
        IF (NOT transports) AND (NOT is_device_compiland) AND
           InitckPointerTk(routines[ri].param_tk[i + 1]) THEN
          InitckReleaseAtCall(v, 0);
        IF transports AND routines[ri].is_extern AND
           InitckPointerTk(routines[ri].param_tk[i + 1]) AND
           NOT IsHostDescriptor(routines[ri].param_tk[i + 1]) THEN
          ptr_actual[i + 1] := v;
        IF track_arg THEN
        BEGIN
          arg_state[i + 1] := EntryAlloca(i1ty, 'initck.actual');
          LLVMBuildStore(builder, EndInitckValue(saved_taint), arg_state[i + 1]);
        END;
      END;
      IF NOT pieces_emitted THEN
      BEGIN
        SetPtrArrayElem(call_args, llvm_ai, v);
        llvm_ai := llvm_ai + 1;
      END;
      initck_taint := outer_taint;
    END;
    initck_call_depth := initck_call_depth - 1;
    InitckFlushReleases(call_base);
    { Publish argument states only now: evaluating later actuals may itself
      call routines that use the side channel. A caller-reset result flag
      makes an uninstrumented callee's result read as initialized. }
    track_ret := InitckResultTracked(ri);
    { A data address a plain EXTERN receives needs the acknowledgement even
      when no state is published (an untracked global descriptor, say). }
    publishes := track_ret;
    FOR i := 1 TO routines[ri].nparams DO
      IF ptr_actual[i] <> NIL THEN publishes := TRUE;
    IF transports THEN
      FOR i := 1 TO routines[ri].nparams DO
        IF arg_state[i] <> NIL THEN
        BEGIN
          LLVMBuildStore(builder, arg_state[i], InitckArgSlot(i));
          publishes := TRUE;
        END;
    IF track_ret THEN
      LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), InitckRetFlag);
    { Tag the call for its callee (InitckAcceptChannel). A plain EXTERN may
      be C, so it also gets a flag that only an instrumented callee sets. }
    ack := NIL;
    IF publishes THEN
    BEGIN
      LLVMBuildStore(builder, LLVMBuildBitCast(builder, routines[ri].fn, i8ptrty, MakeCStr('')),
                     InitckTls('pas_initck_callee', i8ptrty));
      IF routines[ri].is_extern THEN
      BEGIN
        ack := EntryAlloca(i1ty, 'initck.ack');
        LLVMBuildStore(builder, LLVMConstInt(i1ty, 0, 0), ack);
        LLVMBuildStore(builder, LLVMBuildBitCast(builder, ack, i8ptrty, MakeCStr('')),
                       InitckTls('pas_initck_ack', i8ptrty));
      END
      ELSE
        LLVMBuildStore(builder, LLVMConstNull(i8ptrty), InitckTls('pas_initck_ack', i8ptrty));
    END;
    res := LLVMBuildCall2(builder, routines[ri].fnty, routines[ri].fn, call_args, llvm_ai, MakeCStr(''));
    { A Pascal callee clears its slots on entry; clear again in case an
      EXTERN routine was not instrumented, so no slot can dangle. }
    IF transports THEN
      FOR i := 1 TO routines[ri].nparams DO
        IF arg_state[i] <> NIL THEN
          LLVMBuildStore(builder, LLVMConstNull(i8ptrty), InitckArgSlot(i));
    acked := NIL;
    IF ack <> NIL THEN
    BEGIN
      { An unacknowledged EXTERN was not instrumented Pascal: its tag is
        still set, the VAR/CONST storage it was handed may have been written
        by C, and its result state is not a published one. }
      acked := LLVMBuildLoad2(builder, i1ty, ack, MakeCStr('initck.acked'));
      LLVMBuildStore(builder, LLVMConstNull(i8ptrty), InitckTls('pas_initck_callee', i8ptrty));
      LLVMBuildStore(builder, LLVMConstNull(i8ptrty), InitckTls('pas_initck_ack', i8ptrty));
      FOR i := 1 TO routines[ri].nparams DO
      BEGIN
        IF (arg_state[i] <> NIL) AND routines[ri].param_is_var[i] THEN
          InitckReleaseUnacked(acked, arg_state[i], routines[ri].param_tk[i]);
        { The referent of a pointer, or the elements of a descriptor, C
          received, as for a [C] routine; NULL is never registered, so an
          acknowledged call releases nothing. }
        IF ptr_actual[i] <> NIL THEN
          InitckHeapRelease(LLVMBuildSelect(builder, acked, LLVMConstNull(i8ptrty),
            LLVMBuildBitCast(builder, ptr_actual[i], i8ptrty, MakeCStr('')), MakeCStr('')));
      END;
    END;
    IF track_ret AND (initck_taint <> NIL) THEN
    BEGIN
      returned := LLVMBuildLoad2(builder, i1ty, InitckRetFlag, MakeCStr('initck.returned'));
      IF acked <> NIL THEN
        returned := LLVMBuildOr(builder, returned,
                                LLVMBuildNot(builder, acked, MakeCStr('')), MakeCStr(''));
      NoteInitckState(returned);
    END;
    { Attach byval(ty)/align (and sret(ty)/noalias/align for a MEMORY-class
      return) at the CALL SITE too, matching clang's own lowering
      (verification step 7) -- the declaration side alone
      (CodegenRoutineDecl) isn't enough; LLVM expects both. Applies to
      plain-Pascal routines exactly like [C] FOREIGN ones, via the same
      FuncRetAggClass/ClassifyAggregate calls both sides use. Walked with
      its own LLVM argument index (attribute indices are 1-based over LLVM
      parameters, 0 being the return), since a COERCED aggregate argument
      occupies one slot per eightbyte -- and carries no parameter attribute
      at all:
      byval/align describe a pointer to memory, which a register-passed
      aggregate never has. }
    llvm_ai := 0;
    IF ret_class = SYSV_CLASS_MEMORY THEN
    BEGIN
      { The hidden result pointer occupies LLVM argument 0, attribute
        index 1 -- same sret(ty)/noalias/align shape the declaration side
        attaches, since LLVM wants parameter attributes on both. }
      sret_attr := LLVMCreateTypeAttribute(ctx, sret_kind_id, LLVMTypeForTk(routines[ri].ret_tk));
      align_attr := LLVMCreateEnumAttribute(ctx, align_kind_id, SysVByvalAlign(routines[ri].ret_tk));
      LLVMAddCallSiteAttribute(res, 1, sret_attr);
      LLVMAddCallSiteAttribute(res, 1, align_attr);
      IF noalias_kind_id <> 0 THEN
      BEGIN
        noalias_attr := LLVMCreateEnumAttribute(ctx, noalias_kind_id, 0);
        LLVMAddCallSiteAttribute(res, 1, noalias_attr);
      END;
      llvm_ai := 1;
    END;
    FOR i := 0 TO nargs - 1 DO
    BEGIN
      { A variadic tail argument has no formal, so it is always exactly
        one plain LLVM argument and carries no parameter attribute. }
      IF i >= routines[ri].nparams THEN
        llvm_ai := llvm_ai + 1
      ELSE IF routines[ri].param_needs_copy[i + 1] THEN
      BEGIN
        IF is_nvptx_device THEN
          llvm_ai := llvm_ai + 1
        ELSE
        BEGIN
          ClassifyParamAt(routines[ri].param_tk, routines[ri].param_is_var,
                          routines[ri].param_needs_copy, i + 1, ret_class = SYSV_CLASS_MEMORY,
                          agg_class, n_pieces, piece_kind, piece_bytes);
          IF agg_class = SYSV_CLASS_MEMORY THEN
          BEGIN
            byval_attr := LLVMCreateTypeAttribute(ctx, byval_kind_id, LLVMTypeForTk(routines[ri].param_tk[i + 1]));
            align_attr := LLVMCreateEnumAttribute(ctx, align_kind_id, SysVByvalAlign(routines[ri].param_tk[i + 1]));
            LLVMAddCallSiteAttribute(res, llvm_ai + 1, byval_attr);
            LLVMAddCallSiteAttribute(res, llvm_ai + 1, align_attr);
            llvm_ai := llvm_ai + 1;
          END
          ELSE
            llvm_ai := llvm_ai + n_pieces;
        END;
      END
      ELSE
        llvm_ai := llvm_ai + 1;
    END;
    { Turn a [C] aggregate return back into the plain SSA aggregate value
      every caller of this function expects, so the sret/coerced lowering
      stays entirely inside here (mirrors the reference's own
      codegen_c_abi_call tail). }
    IF ret_class = SYSV_CLASS_MEMORY THEN
      res := LLVMBuildLoad2(builder, LLVMTypeForTk(routines[ri].ret_tk), sret_slot, MakeCStr(''))
    ELSE IF ret_class = SYSV_CLASS_COERCED THEN
    BEGIN
      { The register piece(s) came back as the call's own return value:
        write them into real storage of the aggregate's type, viewed as the
        coerced return type, then read the aggregate back out. The slot is
        over-aligned to a full eightbyte for the same reason the callee-side
        COERCED parameter prologue over-aligns its own: the piece store can
        be wider than the aggregate's natural alignment. The slot is typed
        as the COERCED type rather than the aggregate's own, since rounding
        each eightbyte up can make it the larger of the two (e.g. a 12-byte
        ARRAY [1..3] OF INTEGER32 coerces to a 16-byte i64-plus-i32 pair);
        reading
        the aggregate back out of the wider storage is always in bounds,
        the other way round would not be. }
      ret_ll := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
      sret_slot := EntryAlloca(ret_ll, '');
      LLVMSetAlignment(sret_slot, 8);
      LLVMBuildStore(builder, res, sret_slot);
      ret_cptr := LLVMBuildBitCast(builder, sret_slot,
                                   LLVMPointerType(LLVMTypeForTk(routines[ri].ret_tk), 0), MakeCStr(''));
      res := LLVMBuildLoad2(builder, LLVMTypeForTk(routines[ri].ret_tk), ret_cptr, MakeCStr(''));
    END;
    last_val_tk := routines[ri].ret_tk;
  END;
  CodegenCallCommon := res;
END;

PROCEDURE EmitArrayIndexFailure(index_value, lo, hi, site: ADRMEM; unsigned_value: BOOLEAN);
{ Called only in a failed host bounds block, before any GEP or access.
  The selector owns its coordinates; legacy selectors report 0:0. }
VAR
  params, args, fnty, fn, discard: ADRMEM;
  line, column: INTEGER32;
BEGIN
  OperationLocation(site, line, column);
  params := AllocPtrArray(6);
  SetPtrArrayElem(params, 0, i64ty);
  SetPtrArrayElem(params, 1, i32ty);
  SetPtrArrayElem(params, 2, i64ty);
  SetPtrArrayElem(params, 3, i64ty);
  SetPtrArrayElem(params, 4, i32ty);
  SetPtrArrayElem(params, 5, i32ty);
  fnty := LLVMFunctionType(voidty, params, 6, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_array_index_error'));
  IF fn = NIL THEN
    fn := LLVMAddFunction(modl, MakeCStr('pas_array_index_error'), fnty);
  args := AllocPtrArray(6);
  SetPtrArrayElem(args, 0, index_value);
  IF unsigned_value THEN
    SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, 1, 0))
  ELSE
    SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(args, 2, lo);
  SetPtrArrayElem(args, 3, hi);
  SetPtrArrayElem(args, 4, LLVMConstInt(i32ty, line, 0));
  SetPtrArrayElem(args, 5, LLVMConstInt(i32ty, column, 0));
  discard := LLVMBuildCall2(builder, fnty, fn, args, 6, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);
END;

FUNCTION ComputeDesignatorAddress(node: ADRMEM): ADRMEM;
{ Shared by a Designator read (CodegenExpr) and a Designator write
  (CodegenAssignStmt): walk `name` plus zero or more INDEX/FIELD selectors,
  emitting one GEP per selector, and return the final element/field's
  address. Sets last_val_tk to that final element/field's type id, exactly
  like CodegenExpr's own convention -- callers load or store through the
  returned pointer using that type. }
VAR
  nm: Str255;
  symi: INTEGER32;
  base_ptr: ADRMEM;
  cur_tid: INTEGER;
  selectors, sel, idx_expr, gep_idx: ADRMEM;
  nsel, si: INTEGER32;
  kind, fname: Str255;
  idx_val, offset: ADRMEM;
  fi: INTEGER;
  file_handle, file_fcb, file_call_args, file_raw_buf, discard: ADRMEM;
  folded: INTEGER64;
  indexck, unsigned_idx, super_checked: BOOLEAN;
  idx128, i128ty, in_bounds, upper_ok, bad_bb, ok_bb: ADRMEM;
  nil_bad, nil_ok, nil_fnty, nil_fn, is_nil: ADRMEM;
  discard_call: ADRMEM;
  selected_upper, descriptor: ADRMEM;
  deref_ptr_tid: INTEGER; { committed to last_desig_deref_ptr_tid only at
    the end, since index expressions below recurse through here }
  shadow: ADRMEM; { INITCK shadow of the storage selected so far, or NIL;
    committed to last_desig_shadow at the end for the same reason }
  heap_data: ADRMEM; { the tracked referent the last DEREF reached, or NIL }
  super_leaves: ADRMEM; { its i64 leaf count, when it is SUPER ARRAY elements
    whose INDEX comes next; else NIL }
  file_state: ADRMEM; { the whole tracked file buffer state the last DEREF
    reached, or NIL }
  file_state_tid: INTEGER;
BEGIN
  deref_ptr_tid := 0;
  heap_data := NIL;
  file_state := NIL;
  file_state_tid := 0;
  super_leaves := NIL;
  selected_upper := NIL;
  shadow := NIL;
  nm := GetStr(node, 'name');
  symi := LookupSym(nm);
  selectors := GetObj(node, 'selectors');
  nsel := ArrSize(selectors);
  IF NodeType(node) = 'PostfixExpr' THEN
  BEGIN
    { Materialize one function result before walking its selectors. }
    file_handle := CodegenExpr(GetObj(node, 'base'));
    cur_tid := last_val_tk;
    base_ptr := EntryAlloca(LLVMTypeForTk(cur_tid), '');
    LLVMBuildStore(builder, file_handle, base_ptr);
  END
  ELSE IF (symi = 0) AND (nsel = 0) AND RoutineIsFunc(LookupRoutine(nm)) THEN
  BEGIN
    { A bare niladic-call Designator (e.g. `CurKind = 'X'`, an aggregate
      Str255-returning FUNCTION called without parens) has no symbol-table
      entry of its own -- materialize the call's result into a fresh
      temporary and hand back that temporary's address, mirroring the
      reference's get_string_chars_and_len is_bare_func_ref handling. The
      selector loop below is a no-op since nsel = 0 here. }
    cur_tid := routines[LookupRoutine(nm)].ret_tk;
    base_ptr := EntryAlloca(LLVMTypeForTk(cur_tid), '');
    LLVMBuildStore(builder, CodegenCallCommon(nm, NIL), base_ptr);
  END
  ELSE
  BEGIN
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', nm);
    base_ptr := symbols[symi].llvm_val;
    cur_tid := symbols[symi].tk;
    IF InitckTracked(symi) THEN shadow := symbols[symi].init_state;
  END;

  FOR si := 0 TO nsel - 1 DO
  BEGIN
    sel := ArrItem(selectors, si);
    kind := GetStr(sel, 'kind');
    deref_ptr_tid := 0;
    IF kind = 'INDEX' THEN
    BEGIN
      IF (TypeKind(cur_tid) <> TK_ARRAY) AND (TypeKind(cur_tid) <> TK_LSTRING)
        AND (TypeKind(cur_tid) <> TK_STRING) AND (TypeKind(cur_tid) <> TK_VECTOR) THEN
        AbortWith('codegen: an INDEX selector was applied to a non-array');
      { Per-selector state, never inherited from CodegenStmt. Keep this
        local across recursive CodegenExpr calls. Legacy ASTs omit the
        snapshot and use the language default (on). }
      indexck := TRUE;
      IF HasKey(sel, 'indexck') THEN indexck := GetBool(sel, 'indexck');
      idx_expr := GetObj(sel, 'index_or_field');
      IF (TypeKind(cur_tid) = TK_ARRAY) AND NOT is_device_compiland THEN
        IF types[cur_tid].is_super AND (selected_upper = NIL) THEN
          AbortWith('codegen: borrowed SUPER ARRAY subscript has no descriptor bound');
      { A vector lane index is 0-based (types[].lo = 0). A constant lane
        index outside 0..lanes-1 is a compile-time error -- the same
        re-validation M0 does for the type itself, since this file also
        lowers frozen ASTs the typechecker never saw. A variable vector
        index is not range-checked. }
      IF (TypeKind(cur_tid) = TK_VECTOR) AND IsIntLiteralLike(idx_expr) AND
         FoldConstInt(idx_expr, folded) THEN
        IF (folded < 0) OR (folded > types[cur_tid].hi) THEN
          AbortWith('codegen: vector lane index out of range');
      idx_val := CodegenExpr(idx_expr);
      { Fixed ARRAY selectors are guarded against their static bounds and
        host descriptor-backed SUPER ARRAY selectors against the selected
        descriptor's declared lower and actual dynamic upper. Even a
        constant outside the bounds takes the runtime failure branch when
        its access runs, not a compile-time error. A SUPER ARRAY's stored
        hi is a placeholder, so the guard reads the descriptor upper the
        DEREF selector captured; string and vector selectors retain their
        existing behavior. Compare the original index before narrowing or
        subtracting lo, once per selector. }
      IF indexck AND (NOT is_device_compiland) AND
         (TypeKind(cur_tid) = TK_ARRAY) AND (NOT types[cur_tid].is_super) THEN
      BEGIN
        unsigned_idx := (last_val_tk = TK_CHAR) OR
          (last_val_tk = TK_BOOLEAN) OR (TypeKind(last_val_tk) = TK_ENUM) OR
          IsUnsignedWordTk(last_val_tk);
        IF NOT (unsigned_idx OR IsIntegerFamilyTk(last_val_tk)) THEN
          AbortWith('codegen: an array index must be an ordinal type');
        i128ty := LLVMIntTypeInContext(ctx, 128);
        { Only an INTEGER constant expression may have lost its mathematical
          value when CodegenExpr materialized it as vintage i16 (e.g. 40000).
          Never substitute a signed INTEGER64 fold for a typed WORD/CHAR/enum
          value: in particular MAXWORD64 must zero-extend its live i64 bits.
          IsIntLiteralLike refuses a name that CodegenExpr resolved to a
          variable or user routine rather than to the CONST or intrinsic.
          The expression itself was evaluated exactly once above. }
        IF (last_val_tk = TK_INTEGER) AND IsIntLiteralLike(idx_expr) AND
           FoldConstInt(idx_expr, folded) AND
           ((folded < -32768) OR (folded > 32767)) THEN
          idx128 := LLVMConstInt(i128ty, folded, 1)
        ELSE IF unsigned_idx THEN
          idx128 := LLVMBuildZExt(builder, idx_val, i128ty, MakeCStr(''))
        ELSE
          idx128 := LLVMBuildSExt(builder, idx_val, i128ty, MakeCStr(''));
        in_bounds := LLVMBuildICmp(builder, LLVMIntSGE, idx128,
          LLVMConstInt(i128ty, types[cur_tid].lo, 1), MakeCStr(''));
        upper_ok := LLVMBuildICmp(builder, LLVMIntSLE, idx128,
          LLVMConstInt(i128ty, types[cur_tid].hi, 1), MakeCStr(''));
        in_bounds := LLVMBuildAnd(builder, in_bounds, upper_ok, MakeCStr(''));
        bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('index.bad'));
        ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('index.ok'));
        LLVMBuildCondBr(builder, in_bounds, ok_bb, bad_bb);
        LLVMPositionBuilderAtEnd(builder, bad_bb);
        { Diagnose the original, full-width index before forming any GEP.
          Pass its low 64 bits and signedness separately so WORD64 prints
          as unsigned, just as the i128 guard compares it. DEVICE
          compilands never enter this host-only path. }
        EmitArrayIndexFailure(LLVMBuildTrunc(builder, idx128, i64ty, MakeCStr('')),
          LLVMConstInt(i64ty, types[cur_tid].lo, 1),
          LLVMConstInt(i64ty, types[cur_tid].hi, 1), sel, unsigned_idx);
        LLVMPositionBuilderAtEnd(builder, ok_bb);
      END;
      { A descriptor-backed SUPER ARRAY selector checks against the actual
        upper bound the DEREF selector captured. NEW and UNSAFESUPER both
        reject uppers above INT64_MAX, so sign-extending the i64 descriptor
        upper to i128 is faithful; the widened comparison covers signed and
        unsigned indexes alike, and the offset path below reuses the
        checked full-width value. The same once-only index evaluation and
        INTEGER-constant preservation rules as the fixed-array guard apply;
        $INDEXCK- suppresses this guard exactly like the fixed-array one. }
      super_checked := FALSE;
      IF indexck AND (NOT is_device_compiland) AND
         (TypeKind(cur_tid) = TK_ARRAY) AND types[cur_tid].is_super AND
         (selected_upper <> NIL) THEN
      BEGIN
        { A NIL descriptor fails deterministically before any bound
          comparison or address formation: the bad block below only
          diagnoses and never forms a GEP. The index expression has
          already run exactly once above; whether its side effects happen
          before this failure is deliberately not pinned down. }
        is_nil := LLVMBuildICmp(builder, LLVMIntEQ, base_ptr,
          LLVMConstPointerNull(i8ptrty), MakeCStr(''));
        nil_bad := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('index.nil'));
        nil_ok := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('index.nilk'));
        LLVMBuildCondBr(builder, is_nil, nil_bad, nil_ok);
        LLVMPositionBuilderAtEnd(builder, nil_bad);
        nil_fnty := LLVMFunctionType(voidty, AllocPtrArray(0), 0, 0);
        nil_fn := LLVMGetNamedFunction(modl, MakeCStr('pas_super_index_nil_error'));
        IF nil_fn = NIL THEN
          nil_fn := LLVMAddFunction(modl, MakeCStr('pas_super_index_nil_error'), nil_fnty);
        discard_call := LLVMBuildCall2(builder, nil_fnty, nil_fn, AllocPtrArray(0), 0, MakeCStr(''));
        discard_call := LLVMBuildUnreachable(builder);
        LLVMPositionBuilderAtEnd(builder, nil_ok);
        unsigned_idx := (last_val_tk = TK_CHAR) OR
          (last_val_tk = TK_BOOLEAN) OR (TypeKind(last_val_tk) = TK_ENUM) OR
          IsUnsignedWordTk(last_val_tk);
        IF NOT (unsigned_idx OR IsIntegerFamilyTk(last_val_tk)) THEN
          AbortWith('codegen: a super-array index must be ordinal');
        i128ty := LLVMIntTypeInContext(ctx, 128);
        IF (last_val_tk = TK_INTEGER) AND IsIntLiteralLike(idx_expr) AND
           FoldConstInt(idx_expr, folded) AND
           ((folded < -32768) OR (folded > 32767)) THEN
          idx128 := LLVMConstInt(i128ty, folded, 1)
        ELSE IF unsigned_idx THEN
          idx128 := LLVMBuildZExt(builder, idx_val, i128ty, MakeCStr(''))
        ELSE
          idx128 := LLVMBuildSExt(builder, idx_val, i128ty, MakeCStr(''));
        in_bounds := LLVMBuildICmp(builder, LLVMIntSGE, idx128,
          LLVMConstInt(i128ty, types[cur_tid].lo, 1), MakeCStr(''));
        upper_ok := LLVMBuildICmp(builder, LLVMIntSLE, idx128,
          LLVMBuildSExt(builder, selected_upper, i128ty, MakeCStr('')), MakeCStr(''));
        in_bounds := LLVMBuildAnd(builder, in_bounds, upper_ok, MakeCStr(''));
        bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('index.bad'));
        ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('index.ok'));
        LLVMBuildCondBr(builder, in_bounds, ok_bb, bad_bb);
        LLVMPositionBuilderAtEnd(builder, bad_bb);
        { Same diagnostic as a fixed-array failure, but hi is the selected
          descriptor's actual upper. No data address is touched before the
          comparison; the GEP below only runs in the ok block. }
        EmitArrayIndexFailure(LLVMBuildTrunc(builder, idx128, i64ty, MakeCStr('')),
          LLVMConstInt(i64ty, types[cur_tid].lo, 1), selected_upper, sel, unsigned_idx);
        LLVMPositionBuilderAtEnd(builder, ok_bb);
        idx_val := LLVMBuildTrunc(builder, idx128, i64ty, MakeCStr(''));
        super_checked := TRUE;
      END;
      { The reference codegen (resolve_designator_ptr_typed, types_map.py)
        accepts any integer-family index width -- it just subtracts the
        lower bound using a constant of the index's own LLVM type and lets
        GEP take an index of whatever width it is, not just a plain
        16-bit INTEGER. Match that here instead of requiring TK_INTEGER. }
      IF (NOT is_device_compiland) AND (TypeKind(cur_tid) = TK_ARRAY) AND types[cur_tid].is_super THEN
      BEGIN
        IF NOT super_checked THEN
        BEGIN
          IF (last_val_tk = TK_INTEGER) AND IsIntLiteralLike(idx_expr) AND FoldConstInt(idx_expr, folded) THEN
            idx_val := LLVMConstInt(i64ty, folded, 1)
          ELSE IF (last_val_tk <> TK_INTEGER64) AND (last_val_tk <> TK_WORD64) THEN
            IF IsUnsignedWordTk(last_val_tk) OR (last_val_tk = TK_CHAR) OR
               (last_val_tk = TK_BOOLEAN) OR (TypeKind(last_val_tk) = TK_ENUM) THEN
              idx_val := LLVMBuildZExt(builder, idx_val, i64ty, MakeCStr(''))
            ELSE IF IsIntegerFamilyTk(last_val_tk) THEN
              idx_val := LLVMBuildSExt(builder, idx_val, i64ty, MakeCStr(''))
            ELSE AbortWith('codegen: a super-array index must be ordinal');
        END;
        offset := LLVMBuildSub(builder, idx_val, LLVMConstInt(i64ty, types[cur_tid].lo, 1), MakeCStr(''));
      END
      ELSE IF indexck AND (NOT is_device_compiland) AND
         (TypeKind(cur_tid) = TK_ARRAY) AND (NOT types[cur_tid].is_super) THEN
      BEGIN
        { A checked fixed-array offset is nonnegative and at most 65535.
          Reuse the already-checked full value: GEP treats its index as
          signed, so subtracting in i8/i16 would turn a legal WORD8/WORD
          offset (e.g. 255) into a negative address. }
        offset := LLVMBuildSub(builder,
          LLVMBuildTrunc(builder, idx128, i64ty, MakeCStr('')),
          LLVMConstInt(i64ty, types[cur_tid].lo, 1), MakeCStr(''));
      END
      ELSE IF (last_val_tk = TK_CHAR) OR (last_val_tk = TK_BOOLEAN) OR
         (TypeKind(last_val_tk) = TK_ENUM) THEN
      BEGIN
        { A CHAR (i8), BOOLEAN (i1) or enumeration (i32) index is unsigned:
          zero-extend it to i32 before subtracting the low bound, so CHAR
          values past 127 and TRUE do not become negative offsets. }
        IF TypeKind(last_val_tk) <> TK_ENUM THEN
          idx_val := LLVMBuildZExt(builder, idx_val, i32ty, MakeCStr(''));
        offset := LLVMBuildSub(builder, idx_val, LLVMConstInt(i32ty, types[cur_tid].lo, 1), MakeCStr(''));
      END
      ELSE IF (last_val_tk <> TK_INTEGER) AND (last_val_tk <> TK_WORD)
        AND (last_val_tk <> TK_INTEGER8) AND (last_val_tk <> TK_WORD8)
        AND (last_val_tk <> TK_INTEGER32) AND (last_val_tk <> TK_WORD32)
        AND (last_val_tk <> TK_INTEGER64) AND (last_val_tk <> TK_WORD64) THEN
        AbortWith('codegen: an array index must be an ordinal type')
      ELSE
      BEGIN
        { Guard enablement must not change legal addresses. Widen before
          subtraction: narrow GEP indexes are signed, and even a signed
          index can have a nonnegative offset larger than its own range. }
        IF (last_val_tk = TK_INTEGER) AND IsIntLiteralLike(idx_expr) AND FoldConstInt(idx_expr, folded) THEN
          idx_val := LLVMConstInt(i64ty, folded, 1)
        ELSE IF (last_val_tk <> TK_INTEGER64) AND (last_val_tk <> TK_WORD64) THEN
          IF IsUnsignedWordTk(last_val_tk) THEN
            idx_val := LLVMBuildZExt(builder, idx_val, i64ty, MakeCStr(''))
          ELSE
            idx_val := LLVMBuildSExt(builder, idx_val, i64ty, MakeCStr(''));
        offset := LLVMBuildSub(builder, idx_val, LLVMConstInt(i64ty, types[cur_tid].lo, 1), MakeCStr(''));
      END;
      IF types[cur_tid].is_super THEN
      BEGIN
        gep_idx := AllocPtrArray(1);
        SetPtrArrayElem(gep_idx, 0, offset);
        base_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(cur_tid), base_ptr, gep_idx, 1, MakeCStr(''));
      END
      ELSE
      BEGIN
        gep_idx := AllocPtrArray(2);
        SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
        SetPtrArrayElem(gep_idx, 1, offset);
        base_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(cur_tid), base_ptr, gep_idx, 2, MakeCStr(''));
      END;
      { The element's shadow reuses the same, already checked offset: the
        index ran exactly once above and any bounds failure precedes it. }
      IF (shadow <> NIL) AND (TypeKind(cur_tid) = TK_ARRAY) AND
         (NOT types[cur_tid].is_super) THEN
        shadow := LLVMBuildGEP2(builder, InitckShadowTy(cur_tid), shadow, gep_idx, 2,
                                MakeCStr('initck.elem'))
      ELSE IF (super_leaves <> NIL) AND (TypeKind(cur_tid) = TK_ARRAY) AND
              types[cur_tid].is_super THEN
        shadow := InitckSuperElement(heap_data, super_leaves, offset, cur_tid)
      ELSE shadow := NIL;
      super_leaves := NIL;
      cur_tid := types[cur_tid].elem_tid;
      selected_upper := NIL;
    END
    ELSE IF kind = 'DEREF' THEN
    BEGIN
      IF TypeKind(cur_tid) = TK_FILE THEN
      BEGIN
        { F^: the runtime-owned current-component buffer, mirroring the
          reference's _file_buffer_ptr. TEXT files get a lazy-touch hook
          first (touch=True only for ASCII structure, types[].hi = 1). }
        heap_data := NIL;
        file_handle := LLVMBuildLoad2(builder, i8ptrty, base_ptr, MakeCStr(''));
        file_fcb := LLVMBuildBitCast(builder, file_handle, LLVMPointerType(filefcbty, 0), MakeCStr(''));
        file_call_args := AllocPtrArray(1);
        SetPtrArrayElem(file_call_args, 0, file_fcb);
        IF types[cur_tid].hi = 1 THEN
          discard := LLVMBuildCall2(builder, file_touch_buffer_fnty, file_touch_buffer_fn, file_call_args, 1, MakeCStr(''));
        file_raw_buf := LLVMBuildCall2(builder, file_buffer_fnty, file_buffer_fn, file_call_args, 1, MakeCStr(''));
        cur_tid := types[cur_tid].elem_tid;
        base_ptr := LLVMBuildBitCast(builder, file_raw_buf, LLVMPointerType(LLVMTypeForTk(cur_tid), 0), MakeCStr(''));
        { The buffer's state lives beside it (InitFileStorage) and is read
          after pas_file_buffer has completed any deferred fill. }
        shadow := NIL;
        file_state := NIL;
        IF (InitckShadowSize(cur_tid) > 0) AND NOT is_device_compiland THEN
        BEGIN
          file_state := InitckFileState(file_fcb);
          file_state_tid := cur_tid;
          shadow := file_state;
        END;
      END
      ELSE BEGIN
        IF TypeKind(cur_tid) <> TK_POINTER THEN
          AbortWith('codegen: a DEREF selector was applied to a non-pointer');
        { Tracked pointer storage is read here, before the native load. }
        IF shadow <> NIL THEN GuardInitckPointer(node, si, shadow);
        shadow := NIL;
        heap_data := NIL;
        file_state := NIL;
        super_leaves := NIL;
        base_ptr := LLVMBuildLoad2(builder, LLVMTypeForTk(cur_tid), base_ptr, MakeCStr(''));
        selected_upper := NIL;
        IF IsHostDescriptor(cur_tid) THEN
        BEGIN
          descriptor := base_ptr;
          selected_upper := LLVMBuildExtractValue(builder, descriptor, 1, MakeCStr(''));
          base_ptr := LLVMBuildExtractValue(builder, descriptor, 0, MakeCStr(''));
          { The elements' state is found per element at the INDEX below,
            within the allocation's leaves for this descriptor's bounds. }
          IF InitckSuperHeapTracked(cur_tid) THEN
          BEGIN
            heap_data := base_ptr;
            super_leaves := InitckSuperLeaves(selected_upper, types[cur_tid].elem_tid);
          END;
        END
        ELSE IF InitckHeapTracked(cur_tid) THEN
        BEGIN
          { The referent's state, found by its address (registered by NEW). }
          heap_data := base_ptr;
          shadow := InitckHeapShadow(base_ptr, cur_tid);
        END;
        deref_ptr_tid := cur_tid;
        cur_tid := types[cur_tid].elem_tid;
      END;
    END
    ELSE IF kind = 'FIELD' THEN
    BEGIN
      selected_upper := NIL;
      IF TypeKind(cur_tid) = TK_LSTRING THEN
      BEGIN
        shadow := NIL;
        { LSTRING.LEN: the leading length byte, which is simply element 0 of
          the same storage (cg_decl.pas's index-0-is-length convention), so
          this is the INDEX path above with a constant zero. The result is a
          CHAR, and it is an address like any other -- assigning to it is how
          a program truncates the string in place. }
        IF UpperStr(GetStr(sel, 'index_or_field')) <> 'LEN' THEN
          AbortWith2('codegen: an LSTRING has no field: ', GetStr(sel, 'index_or_field'));
        IF types[cur_tid].is_super THEN
        BEGIN
          gep_idx := AllocPtrArray(1);
          SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
          base_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(cur_tid), base_ptr, gep_idx, 1, MakeCStr(''));
        END
        ELSE
        BEGIN
          gep_idx := AllocPtrArray(2);
          SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
          SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
          base_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(cur_tid), base_ptr, gep_idx, 2, MakeCStr(''));
        END;
        cur_tid := types[cur_tid].elem_tid;
      END
      ELSE BEGIN
        IF TypeKind(cur_tid) <> TK_RECORD THEN
          AbortWith('codegen: a FIELD selector was applied to a non-record');
        fname := GetStr(sel, 'index_or_field');
        fi := LookupField(cur_tid, fname);
        IF fi = 0 THEN
          AbortWith2('codegen: unknown record field: ', fname);
        gep_idx := AllocPtrArray(1);
        SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, fields[fi].byte_offset, 0));
        base_ptr := LLVMBuildGEP2(builder, i8ty, base_ptr, gep_idx, 1, MakeCStr(''));
        IF shadow <> NIL THEN
        BEGIN
          gep_idx := AllocPtrArray(1);
          SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, InitckFieldShadowOffset(fi), 0));
          shadow := LLVMBuildGEP2(builder, i1ty, shadow, gep_idx, 1, MakeCStr('initck.field'));
        END;
        cur_tid := fields[fi].field_tid;
        base_ptr := LLVMBuildBitCast(builder, base_ptr, LLVMPointerType(LLVMTypeForTk(cur_tid), 0), MakeCStr(''));
      END;
    END
    ELSE
      AbortWith2('codegen: unhandled selector kind: ', kind);
  END;

  { The prepass marked a designator that hands heap storage to an
    unmodeled alias or effect (ValidateInitckDesignator): release the
    referent it reaches, which no longer has modeled state. }
  IF (heap_data <> NIL) AND HasKey(node, 'initck_release') THEN
  BEGIN
    InitckHeapRelease(heap_data);
    shadow := NIL;
  END;
  { A file buffer handed to an unmodeled effect: initialized until its next
    transition (fill, EOF, PUT, ...) resets it. }
  IF (file_state <> NIL) AND HasKey(node, 'initck_release') THEN
  BEGIN
    InitckTransferShadow(file_state, NIL, file_state_tid, LLVMConstInt(i1ty, 1, 0));
    shadow := NIL;
  END;
  last_val_tk := cur_tid;
  last_desig_deref_ptr_tid := deref_ptr_tid;
  last_desig_super_upper := selected_upper;
  last_desig_shadow := shadow;
  ComputeDesignatorAddress := base_ptr;
END;

FUNCTION VectorArrayOperand(node: ADRMEM; VAR arr_tid: INTEGER;
                            VAR super_upper: ADRMEM): ADRMEM;
VAR
  symi: INTEGER32;
  ptr_tid: INTEGER;
  res: ADRMEM;
BEGIN
  super_upper := NIL;
  res := NIL;
  arr_tid := 0;
  IF NodeType(node) = 'Identifier' THEN
  BEGIN
    symi := LookupSym(GetStr(node, 'name'));
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', GetStr(node, 'name'));
    res := symbols[symi].llvm_val;
    arr_tid := symbols[symi].tk;
  END
  ELSE IF NodeType(node) = 'Designator' THEN
  BEGIN
    res := ComputeDesignatorAddress(node);
    arr_tid := last_val_tk;
    ptr_tid := last_desig_deref_ptr_tid;
    IF ptr_tid <> 0 THEN
      IF (types[ptr_tid].ptr_space = PTR_SPACE_PLAIN) AND (NOT is_device_compiland) THEN
        super_upper := last_desig_super_upper;
  END
  ELSE
    AbortWith('codegen: VLOAD/VSTORE first argument must be an array variable or designator');
  VectorArrayOperand := res;
END;

FUNCTION IsDeviceUnsupportedTranscendental(nm: Str255): BOOLEAN;
{ The libm-backed builtins that the NVPTX path cannot provide.  Keep this
  case-insensitive for the generic body-less EXTERN path. }
VAR
  u: Str255;
BEGIN
  u := UpperStr(nm);
  IsDeviceUnsupportedTranscendental :=
    (u = 'SQRT') OR (u = 'SIN') OR (u = 'COS') OR (u = 'LN') OR
    (u = 'EXP') OR (u = 'ARCTAN');
END;

FUNCTION CodegenIntAbsSqr(is_abs: BOOLEAN; v: ADRMEM; argtk: INTEGER; site: ADRMEM): ADRMEM;
{ Integer-family ABS/SQR at the argument's own width. A WORD-family ABS is
  its argument (never negative). Signed ABS negates a negative value; as a
  checked 0 - v under MATHCK+ (the call's own snapshot) only the minimum
  overflows, which is exactly ABS's overflow. SQR is v * v, checked under
  MATHCK+. MATHCK-, legacy nodes and NVPTX wrap. A fully constant call was
  range-checked by the typechecker and is materialized at its resolved
  type. }
VAR
  folded_tk, tk: INTEGER;
  checked: BOOLEAN;
  zero, neg, is_neg, res: ADRMEM;
BEGIN
  folded_tk := FoldedOperationTk(site);
  IF folded_tk <> TK_UNKNOWN THEN
  BEGIN
    res := LLVMConstInt(LLVMTypeForTk(folded_tk), IntLiteralValue(site), 1);
    last_val_tk := folded_tk;
  END
  ELSE
  BEGIN
    tk := TypeKind(argtk);
    checked := SiteMathCk(site) AND NOT is_nvptx_device;
    { WORD-family ABS has no arithmetic to check. }
    IF SiteMathCk(site) AND is_nvptx_device AND
       NOT (is_abs AND IsUnsignedWordTk(tk)) THEN
      MathckDeviceBoundary(site);
    IF NOT is_abs THEN
    BEGIN
      IF checked THEN res := CodegenCheckedUnary('MUL', v, v, v, 8, tk, site)
      ELSE res := LLVMBuildMul(builder, v, v, MakeCStr(''));
    END
    ELSE IF IsUnsignedWordTk(tk) THEN
      res := v
    ELSE
    BEGIN
      zero := LLVMConstInt(LLVMTypeForTk(tk), 0, 0);
      IF checked THEN neg := CodegenCheckedUnary('MINUS', zero, v, v, 7, tk, site)
      ELSE neg := LLVMBuildSub(builder, zero, v, MakeCStr(''));
      is_neg := LLVMBuildICmp(builder, LLVMIntSLT, v, zero, MakeCStr(''));
      res := LLVMBuildSelect(builder, is_neg, neg, v, MakeCStr(''));
    END;
    last_val_tk := argtk;
  END;
  CodegenIntAbsSqr := res;
END;

FUNCTION RealArgToDouble(v: ADRMEM; argtk: INTEGER): ADRMEM;
{ Bring a builtin's numeric argument to REAL (double) for the libm calls,
  TRUNC, ROUND, and FLOAT: a REAL stays as it is, a REAL32 widens with
  fpext, and an integer converts by its own signedness (IntToFloat).
  sitofp on a float is invalid IR. }
BEGIN
  IF argtk = TK_REAL THEN RealArgToDouble := v
  ELSE IF argtk = TK_REAL32 THEN RealArgToDouble := LLVMBuildFPExt(builder, v, dblty, MakeCStr(''))
  ELSE RealArgToDouble := IntToFloat(v, argtk, dblty);
END;

FUNCTION CodegenCheckedRealToInt(t, arg: ADRMEM; kind: INTEGER; site: ADRMEM): ADRMEM;
{ TRUNC (kind 0) and ROUND (kind 1): t is the value to truncate toward zero
  (ROUND has already added its signed half). IBM checks the INTEGER range
  unconditionally, so this is independent of MATHCK: t must lie strictly
  between -32769 and 32768, and the ordered compares also reject NaN; the
  failure reports the argument at the function name. A bare fptosi would be
  LLVM poison out of range. NVPTX has no host failure path, so device code
  saturates (llvm.fptosi.sat; NaN gives 0) instead of failing. }
VAR
  in_range, bad_bb, ok_bb, ps, fnty, fn, args, discard: ADRMEM;
  line, column: INTEGER32;
BEGIN
  IF is_nvptx_device THEN
  BEGIN
    ps := AllocPtrArray(1);
    SetPtrArrayElem(ps, 0, dblty);
    fnty := LLVMFunctionType(i16ty, ps, 1, 0);
    fn := LLVMGetNamedFunction(modl, MakeCStr('llvm.fptosi.sat.i16.f64'));
    IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('llvm.fptosi.sat.i16.f64'), fnty);
    CodegenCheckedRealToInt := LLVMBuildCall2(builder, fnty, fn, MakeArgs1(t), 1, MakeCStr(''));
    RETURN;
  END;
  in_range := LLVMBuildAnd(builder,
    LLVMBuildFCmp(builder, LLVMRealOGT, t, LLVMConstReal(dblty, -32769.0), MakeCStr('')),
    LLVMBuildFCmp(builder, LLVMRealOLT, t, LLVMConstReal(dblty, 32768.0), MakeCStr('')),
    MakeCStr('conv.in'));
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('conv.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('conv.ok'));
  LLVMBuildCondBr(builder, in_range, ok_bb, bad_bb);
  LLVMPositionBuilderAtEnd(builder, bad_bb);
  ps := AllocPtrArray(4);
  SetPtrArrayElem(ps, 0, i32ty);
  SetPtrArrayElem(ps, 1, dblty);
  SetPtrArrayElem(ps, 2, i32ty);
  SetPtrArrayElem(ps, 3, i32ty);
  fnty := LLVMFunctionType(voidty, ps, 4, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_conversion_error'));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_conversion_error'), fnty);
  OperationLocation(site, line, column);
  args := AllocPtrArray(4);
  SetPtrArrayElem(args, 0, LLVMConstInt(i32ty, kind, 0));
  SetPtrArrayElem(args, 1, arg);
  SetPtrArrayElem(args, 2, LLVMConstInt(i32ty, line, 0));
  SetPtrArrayElem(args, 3, LLVMConstInt(i32ty, column, 0));
  discard := LLVMBuildCall2(builder, fnty, fn, args, 4, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
  CodegenCheckedRealToInt := LLVMBuildFPToSI(builder, t, i16ty, MakeCStr(''));
END;

PROCEDURE EmitChrCheck(v: ADRMEM; argtk: INTEGER; site: ADRMEM);
{ Check the original integer before truncation. Unlike an i64 signed upper
  bound alone, unsigned ULE also rejects WORD64's high-bit values. }
VAR
  enabled, unsigned_value: BOOLEAN;
  bits, ok, bad_bb, ok_bb, ps, fnty, fn, args, discard: ADRMEM;
  line, column: INTEGER32;
BEGIN
  enabled := cur_rangeck;
  IF HasKey(site, 'rangeck') THEN enabled := GetBool(site, 'rangeck');
  IF NOT enabled OR is_nvptx_device THEN RETURN;
  unsigned_value := IsUnsignedWordTk(argtk);
  bits := v;
  IF LLVMTypeForTk(argtk) <> i64ty THEN
  BEGIN
    IF unsigned_value THEN bits := LLVMBuildZExt(builder, bits, i64ty, MakeCStr(''))
    ELSE bits := LLVMBuildSExt(builder, bits, i64ty, MakeCStr(''));
  END;
  ok := LLVMBuildICmp(builder, LLVMIntULE, bits, LLVMConstInt(i64ty, 255, 0), MakeCStr('chr.in'));
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('chr.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('chr.ok'));
  LLVMBuildCondBr(builder, ok, ok_bb, bad_bb);
  LLVMPositionBuilderAtEnd(builder, bad_bb);
  ps := AllocPtrArray(4);
  SetPtrArrayElem(ps, 0, i64ty);
  SetPtrArrayElem(ps, 1, i32ty);
  SetPtrArrayElem(ps, 2, i32ty);
  SetPtrArrayElem(ps, 3, i32ty);
  fnty := LLVMFunctionType(voidty, ps, 4, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_chr_error'));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_chr_error'), fnty);
  OperationLocation(site, line, column);
  args := AllocPtrArray(4);
  SetPtrArrayElem(args, 0, bits);
  IF unsigned_value THEN SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, 1, 0))
  ELSE SetPtrArrayElem(args, 1, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(args, 2, LLVMConstInt(i32ty, line, 0));
  SetPtrArrayElem(args, 3, LLVMConstInt(i32ty, column, 0));
  discard := LLVMBuildCall2(builder, fnty, fn, args, 4, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
END;

FUNCTION CodegenSimpleBuiltin(nm: Str255; site: ADRMEM): ADRMEM;
{ The math/ordinal builtins that need no libpascalrt support: pure inline
  LLVM IR (CHR/ORD/ODD/SUCC/PRED/ABS/SQR), or a single libm call
  (SQRT/SIN/COS/LN/EXP/ARCTAN), mirroring the Python reference's exprs.py
  1:1 except where this dialect's INTEGER is 16-bit rather than the
  reference's 32-bit: ORD's result and TRUNC/ROUND's result are produced as
  i16 here, not i32 -- consistent with every other native-INTEGER value in
  this file, and with the dialect's own known 16-bit-INTEGER-overflow
  behavior (not a bug -- see the codebase's own vintage-dialect notes). }
VAR
  v, v2, is_neg, neg, half, res, hi16, lo16, args: ADRMEM;
  argtk, argtk2: INTEGER;
BEGIN
  { NVPTX only: a serial/CPU DEVICE compiland is an ordinary host module in
    address space 0 and links libm like any other, so is_device_compiland is
    the wrong key here. }
  IF is_nvptx_device AND IsDeviceUnsupportedTranscendental(nm) THEN
    AbortWith2('codegen: transcendental math function is not supported in DEVICE code: ', nm);
  args := GetObj(site, 'args');
  v := CodegenExpr(ArrItem(args, 0));
  argtk := last_val_tk;
  IF nm = 'CHR' THEN
  BEGIN
    EmitChrCheck(v, argtk, site);
    IF LLVMTypeForTk(argtk) = i8ty THEN res := v
    ELSE res := LLVMBuildTrunc(builder, v, i8ty, MakeCStr(''));
    last_val_tk := TK_CHAR;
  END
  ELSE IF nm = 'ORD' THEN
  BEGIN
    IF (argtk = TK_CHAR) OR (argtk = TK_BOOLEAN) THEN
    BEGIN
      { Zero-extend, so ORD(TRUE) is 1 rather than a sign-extended i1. }
      res := LLVMBuildZExt(builder, v, i16ty, MakeCStr(''));
      last_val_tk := TK_INTEGER;
    END
    ELSE IF TypeKind(argtk) = TK_ENUM THEN
    BEGIN
      { An enum ordinal is stored as i32, but ORD's result is INTEGER
        (the typechecker's type for it), so narrow it: every ordinal fits.
        An INTEGER32 tag would check later arithmetic at 32 bits and then
        silently truncate the result into an INTEGER target. }
      res := LLVMBuildTrunc(builder, v, i16ty, MakeCStr(''));
      last_val_tk := TK_INTEGER;
    END
    ELSE
    BEGIN
      { An integer keeps its own value and width (so does pasboot); tagging
        an i32 or i64 INTEGER would mix widths in later arithmetic. }
      res := v;
      last_val_tk := argtk;
    END;
  END
  ELSE IF nm = 'ODD' THEN
  BEGIN
    res := LLVMBuildAnd(builder, v, LLVMConstInt(i16ty, 1, 0), MakeCStr(''));
    res := LLVMBuildICmp(builder, LLVMIntNE, res, LLVMConstInt(i16ty, 0, 0), MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF (nm = 'SUCC') OR (nm = 'PRED') THEN
    res := CodegenSuccPred(nm = 'SUCC', v, argtk, site)
  ELSE IF (nm = 'ABS') OR (nm = 'SQR') THEN
  BEGIN
    { ABS and SQR keep the argument's own width: REAL32 stays float, and
      the integer family stays at its own width and signedness. }
    IF (argtk = TK_REAL) OR (argtk = TK_REAL32) THEN
    BEGIN
      IF nm = 'SQR' THEN res := LLVMBuildFMul(builder, v, v, MakeCStr(''))
      ELSE
      BEGIN
        is_neg := LLVMBuildFCmp(builder, LLVMRealOLT, v, LLVMConstReal(LLVMTypeForTk(argtk), 0.0), MakeCStr(''));
        neg := LLVMBuildFSub(builder, LLVMConstReal(LLVMTypeForTk(argtk), 0.0), v, MakeCStr(''));
        res := LLVMBuildSelect(builder, is_neg, neg, v, MakeCStr(''));
      END;
      last_val_tk := argtk;
    END
    ELSE
      res := CodegenIntAbsSqr(nm = 'ABS', v, argtk, site);
  END
  ELSE IF (nm = 'SQRT') OR (nm = 'SIN') OR (nm = 'COS') OR (nm = 'LN') OR (nm = 'EXP') OR (nm = 'ARCTAN') THEN
  BEGIN
    v := RealArgToDouble(v, argtk);
    IF nm = 'SQRT' THEN res := LLVMBuildCall2(builder, sqrt_fnty, sqrt_fn, MakeArgs1(v), 1, MakeCStr(''))
    ELSE IF nm = 'SIN' THEN res := LLVMBuildCall2(builder, sin_fnty, sin_fn, MakeArgs1(v), 1, MakeCStr(''))
    ELSE IF nm = 'COS' THEN res := LLVMBuildCall2(builder, cos_fnty, cos_fn, MakeArgs1(v), 1, MakeCStr(''))
    ELSE IF nm = 'LN' THEN res := LLVMBuildCall2(builder, log_fnty, log_fn, MakeArgs1(v), 1, MakeCStr(''))
    ELSE IF nm = 'EXP' THEN res := LLVMBuildCall2(builder, exp_fnty, exp_fn, MakeArgs1(v), 1, MakeCStr(''))
    ELSE res := LLVMBuildCall2(builder, atan_fnty, atan_fn, MakeArgs1(v), 1, MakeCStr(''));
    last_val_tk := TK_REAL;
  END
  ELSE IF nm = 'TRUNC' THEN
  BEGIN
    v := RealArgToDouble(v, argtk);
    res := CodegenCheckedRealToInt(v, v, 0, site);
    last_val_tk := TK_INTEGER;
  END
  ELSE IF nm = 'ROUND' THEN
  BEGIN
    v := RealArgToDouble(v, argtk);
    is_neg := LLVMBuildFCmp(builder, LLVMRealOLT, v, LLVMConstReal(dblty, 0.0), MakeCStr(''));
    half := LLVMBuildSelect(builder, is_neg, LLVMConstReal(dblty, -0.5), LLVMConstReal(dblty, 0.5), MakeCStr(''));
    res := CodegenCheckedRealToInt(LLVMBuildFAdd(builder, v, half, MakeCStr('')), v, 1, site);
    last_val_tk := TK_INTEGER;
  END
  ELSE IF nm = 'FLOAT' THEN
  BEGIN
    res := RealArgToDouble(v, argtk);
    last_val_tk := TK_REAL;
  END
  ELSE IF (nm = 'HIBYTE') OR (nm = 'LOBYTE') THEN
  BEGIN
    { The reference (typecheck/exprs.py) restricts these to INTEGER/WORD
      arguments only -- not INTEGER8/CHAR/BOOLEAN, despite the codegen
      truncation working for any i16-or-narrower value -- and returns
      CHAR, not a byte-integer type, since HIBYTE/LOBYTE is "the faithful
      dialect pair" that predates the wide-integer extension family. }
    IF (argtk <> TK_INTEGER) AND (argtk <> TK_WORD) THEN
      AbortWith2('codegen: HIBYTE/LOBYTE require an INTEGER/WORD argument: ', nm);
    IF nm = 'HIBYTE' THEN res := LLVMBuildLShr(builder, v, LLVMConstInt(i16ty, 8, 0), MakeCStr(''))
    ELSE res := v;
    res := LLVMBuildTrunc(builder, res, i8ty, MakeCStr(''));
    last_val_tk := TK_CHAR;
  END
  ELSE IF nm = 'WRD8' THEN
  BEGIN
    IF NOT (active_features.wide_integers OR is_device_compiland) THEN
      AbortWith('codegen: WRD8 requires the extended dialect');
    { WRD8(x): truncate/retype to the 8-bit unsigned WORD8 -- the 8-bit
      sibling of WRD. Wider integers truncate to the low byte; i8-width
      values (CHAR/INTEGER8/WORD8) pass through unchanged; BOOLEAN (i1
      here, unlike the reference's i8-loaded BOOLEAN) zero-extends to i8. }
    IF argtk = TK_REAL THEN
      AbortWith('codegen: WRD8: REAL argument not supported');
    IF (argtk = TK_CHAR) OR (argtk = TK_INTEGER8) OR (argtk = TK_WORD8) THEN res := v
    ELSE IF argtk = TK_BOOLEAN THEN res := LLVMBuildZExt(builder, v, i8ty, MakeCStr(''))
    ELSE res := LLVMBuildTrunc(builder, v, i8ty, MakeCStr(''));
    last_val_tk := TK_WORD8;
  END
  ELSE IF nm = 'WRD' THEN
  BEGIN
    { INTEGER/WORD (already i16) pass through unchanged; CHAR/BOOLEAN/
      INTEGER8 (i8) zero-extend to i16 -- matches the reference's WRD,
      whose only width this file can ever produce is <=16 bits (no
      INTEGER32/WORD32 here to exercise its truncating branch). }
    IF (argtk = TK_INTEGER) OR (argtk = TK_WORD) THEN res := v
    ELSE res := LLVMBuildZExt(builder, v, i16ty, MakeCStr(''));
    last_val_tk := TK_WORD;
  END
  ELSE IF nm = 'BYWORD' THEN
  BEGIN
    { Pack two byte-ish values into one WORD: (hi&0xFF)<<8 | (lo&0xFF).
      The reference's BYWORD argument allowlist is INTEGER/WORD/CHAR/
      BOOLEAN only (unlike WRD's, it omits INTEGER8) -- not enforced here
      since this file trusts whatever the typechecker already approved,
      same discipline as every other builtin in this function. }
    v2 := CodegenExpr(ArrItem(args, 1));
    argtk2 := last_val_tk;
    IF (argtk = TK_INTEGER) OR (argtk = TK_WORD) THEN hi16 := v
    ELSE hi16 := LLVMBuildZExt(builder, v, i16ty, MakeCStr(''));
    IF (argtk2 = TK_INTEGER) OR (argtk2 = TK_WORD) THEN lo16 := v2
    ELSE lo16 := LLVMBuildZExt(builder, v2, i16ty, MakeCStr(''));
    hi16 := LLVMBuildAnd(builder, hi16, LLVMConstInt(i16ty, 255, 0), MakeCStr(''));
    lo16 := LLVMBuildAnd(builder, lo16, LLVMConstInt(i16ty, 255, 0), MakeCStr(''));
    res := LLVMBuildOr(builder, LLVMBuildShl(builder, hi16, LLVMConstInt(i16ty, 8, 0), MakeCStr('')), lo16, MakeCStr(''));
    last_val_tk := TK_WORD;
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unsupported builtin: ', nm);
    res := NIL;
  END;
  CodegenSimpleBuiltin := res;
END;

FUNCTION CodegenDevAlloc(args: ADRMEM): ADRMEM;
{ DEVALLOC(n): host-only device-memory allocation (Milestone D). Returns the
  opaque ADRMEM handle DEVCOPYTO/DEVCOPYFROM/DEVFREE/LAUNCH consume. On the
  CPU-device shim this is malloc; mirrors the Python reference's exprs.py. }
VAR
  nbytes: ADRMEM;
BEGIN
  IF is_device_compiland THEN
    AbortWith('codegen: DEVALLOC is host-only and cannot appear in DEVICE code');
  IF ArrSize(args) <> 1 THEN AbortWith('codegen: DEVALLOC expects 1 argument (byte count)');
  nbytes := CodegenExpr(ArrItem(args, 0));
  nbytes := LaunchI64(nbytes, last_val_tk);
  CodegenDevAlloc := LLVMBuildCall2(builder, dev_alloc_fnty, dev_alloc_fn, MakeArgs1(nbytes), 1, MakeCStr(''));
  last_val_tk := TK_ADRMEM;
END;

FUNCTION SetOpResultType(lt, rt: INTEGER): INTEGER;
{ Bounds/representation type of a set operation, not semantic compatibility.
  Matching declared representation bases retain and widen their ranges;
  anonymous constructors contribute generic INTEGER 0..255 bounds even
  when their members have a BOOLEAN, CHAR or enum semantic host. Different
  representation bases also fall back to generic bounds, but incompatible
  semantic hosts have already been rejected by the typechecker. Reuse an
  existing widened type when possible. LOWER/UPPER calls this static walk
  without evaluating either operand. }
VAR
  lo, hi: INTEGER32;
  ti, found: INTEGER;
BEGIN
  { LOWER/UPPER's static type walk must not turn a visibly incompatible
    declared pair into generic bounds if the checker was bypassed. }
  IF DeclaredSetBasesConflict(lt, rt) THEN
    AbortWith('codegen: incompatible declared SET bases');
  IF lt = rt THEN
    SetOpResultType := lt
  ELSE IF types[lt].elem_tid <> types[rt].elem_tid THEN
    SetOpResultType := EnsureGenericSetType
  ELSE
  BEGIN
    lo := types[lt].lo;
    IF types[rt].lo < lo THEN lo := types[rt].lo;
    hi := types[lt].hi;
    IF types[rt].hi > hi THEN hi := types[rt].hi;
    found := 0;
    FOR ti := 14 TO ntypes DO
      IF (found = 0) AND (types[ti].tk = TK_SET) AND
         (types[ti].elem_tid = types[lt].elem_tid) AND
         (types[ti].lo = lo) AND (types[ti].hi = hi) THEN
        found := ti;
    IF found = 0 THEN
      found := RegisterType(TK_SET, types[lt].elem_tid, lo, hi, setty);
    SetOpResultType := found;
  END;
END;

FUNCTION BareFunctionResultType(name: Str255): INTEGER;
{ The result type of a function named without an argument list, or
  TK_UNKNOWN when the name is not a function. }
VAR
  ri: INTEGER32;
BEGIN
  BareFunctionResultType := TK_UNKNOWN;
  ri := LookupRoutine(name);
  IF ri <> 0 THEN
    IF RoutineIsFunc(ri) THEN BareFunctionResultType := routines[ri].ret_tk;
END;

FUNCTION BoundOperandType(node: ADRMEM): INTEGER;
{ Resolve the operand without generating any IR: LOWER and all static
  bounds must not execute calls or index expressions. }
VAR
  nt, name: Str255;
  si: INTEGER32;
  lt, rt: INTEGER;
BEGIN
  nt := NodeType(node);
  IF (nt = 'Designator') OR (nt = 'PostfixExpr') THEN
  BEGIN
    BoundOperandType := StaticDesignatorType(node);
    { A bare name that is no variable may be a parameterless function
      called without parentheses (UPPER(getset)); its bounds are its
      result type's, and the call is not executed. }
    IF (nt = 'Designator') AND (ArrSize(GetObj(node, 'selectors')) = 0) AND
       (LookupSym(GetStr(node, 'name')) = 0) THEN
      BoundOperandType := BareFunctionResultType(GetStr(node, 'name'));
  END
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    name := GetStr(node, 'name');
    si := LookupSym(name);
    IF si <> 0 THEN BoundOperandType := symbols[si].tk
    ELSE BEGIN
      si := LookupConst(name);
      IF si <> 0 THEN BoundOperandType := const_tbl[si].enum_tid
      ELSE BoundOperandType := BareFunctionResultType(name);
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    si := LookupRoutine(GetStr(node, 'name'));
    IF si <> 0 THEN BoundOperandType := routines[si].ret_tk
    ELSE BoundOperandType := TK_UNKNOWN;
  END
  ELSE IF nt = 'SetConstructor' THEN
    BoundOperandType := EnsureGenericSetType
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    lt := BoundOperandType(GetObj(node, 'left'));
    rt := BoundOperandType(GetObj(node, 'right'));
    IF (TypeKind(lt) = TK_SET) AND (TypeKind(rt) = TK_SET) THEN
      BoundOperandType := SetOpResultType(lt, rt)
    ELSE BoundOperandType := TK_UNKNOWN;
  END
  ELSE BoundOperandType := TK_UNKNOWN;
END;

FUNCTION SuperBoundBits(node: ADRMEM; VAR unsigned_flag: ADRMEM): ADRMEM;
VAR v: ADRMEM; tid: INTEGER; folded: INTEGER64; uns: BOOLEAN;
BEGIN
  v := CodegenExpr(node); tid := last_val_tk;
  uns := IsUnsignedWordTk(tid) OR (tid = TK_CHAR) OR (tid = TK_BOOLEAN) OR (TypeKind(tid) = TK_ENUM);
  IF NOT (IsIntegerFamilyTk(tid) OR uns) THEN
    AbortWith('codegen: SUPER ARRAY bounds must be ordinal values');
  IF uns THEN unsigned_flag := LLVMConstInt(i32ty, 1, 0)
  ELSE unsigned_flag := LLVMConstInt(i32ty, 0, 0);
  { Preserve mathematical INTEGER constants before their vintage i16
    materialization. WORD64 bits stay unsigned until runtime validation. }
  IF (tid = TK_INTEGER) AND IsIntLiteralLike(node) AND FoldConstInt(node, folded) THEN
    v := LLVMConstInt(i64ty, folded, 1)
  ELSE IF (tid <> TK_INTEGER64) AND (tid <> TK_WORD64) THEN
    IF uns THEN v := LLVMBuildZExt(builder, v, i64ty, MakeCStr(''))
    ELSE v := LLVMBuildSExt(builder, v, i64ty, MakeCStr(''));
  SuperBoundBits := v;
END;

FUNCTION CodegenUnsafeSuper(args: ADRMEM): ADRMEM;
VAR target, raw_tid, arr_tid: INTEGER;
    raw, lo_bits, hi_bits, lower_uns, upper_uns, params, vals, fnty, fn, discard: ADRMEM;
    domain_low, domain_high: INTEGER64; i: INTEGER;
BEGIN
  IF ArrSize(args) <> 4 THEN AbortWith('codegen: UNSAFESUPER expects (pointer type, raw, lower, upper)');
  IF NodeType(ArrItem(args, 0)) <> 'Identifier' THEN
    AbortWith('codegen: UNSAFESUPER first argument must be a descriptor pointer type name');
  target := LookupNamedType(GetStr(ArrItem(args, 0), 'name'));
  IF NOT IsHostDescriptor(target) THEN
    AbortWith('codegen: UNSAFESUPER target must be a host super-array descriptor pointer');
  arr_tid := types[target].elem_tid;
  SuperDomainLimits(arr_tid, domain_low, domain_high);
  raw := CodegenExpr(ArrItem(args, 1)); raw_tid := last_val_tk;
  IF raw_tid <> TK_ADRMEM THEN
  BEGIN
    IF TypeKind(raw_tid) <> TK_POINTER THEN AbortWith('codegen: UNSAFESUPER raw argument must be a host pointer');
    IF IsHostDescriptor(raw_tid) OR (types[raw_tid].ptr_space <> PTR_SPACE_PLAIN) OR
       (types[raw_tid].elem_tid <> types[arr_tid].elem_tid) THEN
      AbortWith('codegen: UNSAFESUPER raw argument must be CPTR/ADRMEM or a compatible thin element pointer');
  END;
  lo_bits := SuperBoundBits(ArrItem(args, 2), lower_uns);
  hi_bits := SuperBoundBits(ArrItem(args, 3), upper_uns);
  params := AllocPtrArray(10); vals := AllocPtrArray(10);
  FOR i := 0 TO 9 DO SetPtrArrayElem(params, i, i64ty);
  SetPtrArrayElem(params, 0, i8ptrty);
  SetPtrArrayElem(params, 2, i32ty); SetPtrArrayElem(params, 4, i32ty);
  SetPtrArrayElem(vals, 0, raw); SetPtrArrayElem(vals, 1, lo_bits); SetPtrArrayElem(vals, 2, lower_uns);
  SetPtrArrayElem(vals, 3, hi_bits); SetPtrArrayElem(vals, 4, upper_uns);
  SetPtrArrayElem(vals, 5, LLVMConstInt(i64ty, types[arr_tid].lo, 1));
  SetPtrArrayElem(vals, 6, LLVMConstInt(i64ty, domain_low, 1));
  SetPtrArrayElem(vals, 7, LLVMConstInt(i64ty, domain_high, 1));
  SetPtrArrayElem(vals, 8, LLVMConstInt(i64ty, SuperElementSize(types[arr_tid].elem_tid), 0));
  SetPtrArrayElem(vals, 9, LLVMConstInt(i64ty, LLVMABIAlignmentOfType(LLVMGetModuleDataLayout(modl), LLVMTypeForTk(types[arr_tid].elem_tid)), 0));
  fnty := LLVMFunctionType(voidty, params, 10, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr('pas_super_import_check'));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_super_import_check'), fnty);
  discard := LLVMBuildCall2(builder, fnty, fn, vals, 10, MakeCStr(''));
  CodegenUnsafeSuper := MakeDescriptor(target, raw, hi_bits);
  last_val_tk := target;
END;

FUNCTION CodegenExpr(node: ADRMEM): ADRMEM;
VAR
  nt: Str255;
  nm, nm_raw: Str255;
  nmu: Str255;
  symi: INTEGER32;
  consti: INTEGER32;
  routi: INTEGER32;
  ch: Str255;
  res, addr, super_ptr, super_header, bound_operand, bound_sels: ADRMEM;
  nil_bb, ok_bb, is_nil, err_args, discard, nil_fnty, nil_fn: ADRMEM;
  result_tid, static_bound_tid: INTEGER;
  bound_n: INTEGER32;
  target_item, target_str, sizeof_synth: ADRMEM;
  sizeof_bytes: INTEGER32;
  call_args: ADRMEM;
  vsel_mask, vsel_a, vsel_b: ADRMEM;
  vsel_mask_tid, vsel_a_tid, vsel_b_tid: INTEGER;
  vld_idx, vld_arr: ADRMEM;
  vld_idx_tk, vld_arr_tid: INTEGER;
  vld_hdr: ADRMEM;
  bound_is_subrange, saved_rangeck: BOOLEAN;
  range_flags: ADRMEM;
  value_shadow: ADRMEM; { committed to last_value_shadow at the end }
BEGIN
  EnterExprLevel;
  saved_rangeck := cur_rangeck;
  range_flags := GetObjOrNil(node, 'read_flags');
  IF range_flags <> NIL THEN
    IF HasKey(range_flags, 'RANGECK') THEN
      cur_rangeck := GetBool(range_flags, 'RANGECK');
  value_shadow := NIL;
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN
  BEGIN
    { The typechecker's tag is the literal's own type (WORD for
      32768..65535, INTEGER32 above, and so on) or its assignment target's;
      building every literal at i16 wrapped those. A literal tagged INTEGER,
      or untagged legacy input, stays plain INTEGER and still adapts to a
      sibling operand in CodegenBinOp. }
    last_val_tk := FoldedOperationTk(node);
    IF last_val_tk = TK_UNKNOWN THEN last_val_tk := TK_INTEGER;
    res := LLVMConstInt(LLVMTypeForTk(last_val_tk), IntLiteralValue(node), 1);
  END
  ELSE IF nt = 'RealLiteral' THEN
  BEGIN
    target_item := GetObjOrNil(node, 'resolved_type');
    IF (target_item <> NIL) AND
       (GetStr(target_item, '__type_system__') = 'Real32Type') THEN
    BEGIN
      res := LLVMConstReal(f32ty, GetReal(node, 'value'));
      last_val_tk := TK_REAL32;
    END
    ELSE BEGIN
      res := LLVMConstReal(dblty, GetReal(node, 'value'));
      last_val_tk := TK_REAL;
    END;
  END
  ELSE IF nt = 'CharLiteral' THEN
  BEGIN
    ch := GetStr(node, 'value');
    res := LLVMConstInt(i8ty, ORD(ch[1]), 0);
    last_val_tk := TK_CHAR;
  END
  ELSE IF nt = 'BoolLiteral' THEN
  BEGIN
    IF GetBool(node, 'value') THEN res := LLVMConstInt(i1ty, 1, 0)
    ELSE res := LLVMConstInt(i1ty, 0, 0);
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF nt = 'NilLiteral' THEN
  BEGIN
    { the reference codegen types this as a bare i8* null constant; ADRMEM
      is this file's own tag for that same i8ptrty representation, matching
      how the native compiler stages themselves (lexer.pas/parser.pas/
      typechecker.pas) declare their own opaque handles as ADRMEM and
      compare them against NIL. }
    res := LLVMConstNull(i8ptrty);
    last_val_tk := TK_ADRMEM;
  END
  ELSE IF nt = 'AdrExpr' THEN
  BEGIN
    { ADR <var>: the variable's own storage address -- symbols[symi].llvm_val
      already *is* that address (an alloca/global pointer), matching the
      Python reference's `return symbol.llvm_value` (codegen/exprs.py) --
      unlike a plain Identifier reference, this must NOT load through it.
      Typed as ADRMEM (opaque i8*, this file's existing tag for any
      general-purpose pointer-shaped FFI/interop value) rather than a
      registered ^T tid: assignment/argument compatibility already treats
      ADRMEM and any POINTER tid as mutually coercible (see
      TypesCompatibleForAssign's TK_ADRMEM cases), so this is sufficient for
      every caller in this self-hosting subset without adding a new
      per-declaration pointer registration path. }
    symi := LookupSym(GetStr(node, 'name'));
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', GetStr(node, 'name'));
    IF ExposesHostDescriptor(symbols[symi].tk) THEN
      AbortWith('codegen: ADR cannot expose super-array descriptor storage; use UNSAFERAW');
    IF TypeKind(symbols[symi].tk) = TK_ARRAY THEN
      IF types[symbols[symi].tk].is_super THEN
        AbortWith('codegen: ADR of a borrowed SUPER ARRAY is unsupported');
    res := LLVMBuildBitCast(builder, symbols[symi].llvm_val, i8ptrty, MakeCStr(''));
    last_val_tk := TK_ADRMEM;
    { Raw writes through this address are not modeled, so every leaf of the
      tracked slot is released (initialized) where the address becomes
      usable: here, or as an actual at its call, after the later actuals
      (InitckReleaseAtCall); the slot stays tracked (InitckLocalEscapes). A
      WITH-bound field's ADR disqualified its whole object instead, so it
      has no state here. }
    IF InitckTracked(symi) AND NOT symbols[symi].is_with_field THEN
      InitckReleaseAtCall(symbols[symi].init_state, symbols[symi].tk);
  END
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    nm := GetStr(node, 'name');
    nmu := UpperStr(nm);
    { These unsigned maxima have all bits set.  LLVMConstInt takes the
      machine bit pattern through the signed CLONG binding, so -1 is the
      correct i32/i64 payload; WRITE chooses %u/%llu from last_val_tk. }
    IF nmu = 'MAXINT' THEN
    BEGIN
      res := LLVMConstInt(i16ty, 32767, 1);
      last_val_tk := TK_INTEGER;
    END
    ELSE IF nmu = 'MAXWORD' THEN
    BEGIN
      res := LLVMConstInt(i16ty, -1, 0);
      last_val_tk := TK_WORD;
    END
    ELSE IF nmu = 'MAXINT32' THEN
    BEGIN
      res := LLVMConstInt(i32ty, 2147483647, 1);
      last_val_tk := TK_INTEGER32;
    END
    ELSE IF nmu = 'MAXWORD32' THEN
    BEGIN
      res := LLVMConstInt(i32ty, -1, 0);
      last_val_tk := TK_WORD32;
    END
    ELSE IF nmu = 'MAXINT64' THEN
    BEGIN
      res := LLVMConstInt(i64ty, 9223372036854775807, 1);
      last_val_tk := TK_INTEGER64;
    END
    ELSE IF nmu = 'MAXWORD64' THEN
    BEGIN
      res := LLVMConstInt(i64ty, -1, 0);
      last_val_tk := TK_WORD64;
    END
    ELSE IF (nmu = 'THREADIDX_X') OR (nmu = 'THREADIDX_Y') OR (nmu = 'THREADIDX_Z') OR
       (nmu = 'BLOCKIDX_X') OR (nmu = 'BLOCKIDX_Y') OR (nmu = 'BLOCKIDX_Z') OR
       (nmu = 'BLOCKDIM_X') OR (nmu = 'BLOCKDIM_Y') OR (nmu = 'BLOCKDIM_Z') OR
       (nmu = 'GRIDDIM_X') OR (nmu = 'GRIDDIM_Y') OR (nmu = 'GRIDDIM_Z') THEN
      res := CodegenDeviceIndex(nmu)
    ELSE
    BEGIN
    symi := LookupSym(nm);
    IF symi <> 0 THEN
    BEGIN
      GuardInitckRead(node, symi);
      res := LLVMBuildLoad2(builder, LLVMTypeForTk(symbols[symi].tk), symbols[symi].llvm_val, MakeCStr(''));
      last_val_tk := symbols[symi].tk;
      IF InitckTracked(symi) THEN value_shadow := symbols[symi].init_state;
    END
    ELSE
    BEGIN
      consti := LookupConst(nm);
      routi := LookupRoutine(nm);
      IF consti <> 0 THEN
      BEGIN
        IF const_tbl[consti].is_real THEN
        BEGIN
          res := LLVMConstReal(dblty, const_tbl[consti].rval);
          last_val_tk := TK_REAL;
        END
        ELSE IF const_tbl[consti].enum_tid <> 0 THEN
        BEGIN
          res := LLVMConstInt(i32ty, const_tbl[consti].ival, 0);
          last_val_tk := const_tbl[consti].enum_tid;
        END
        ELSE IF const_tbl[consti].is_char THEN
        BEGIN
          { Same shape a bare CharLiteral gets above: an unsigned i8 typed
            TK_CHAR, so WRITELN prints the character rather than its
            ordinal and CHAR assignment/comparison typechecks. }
          res := LLVMConstInt(i8ty, const_tbl[consti].ival, 0);
          last_val_tk := TK_CHAR;
        END
        ELSE
        BEGIN
          last_val_tk := const_tbl[consti].integer_tid;
          IF last_val_tk = 0 THEN last_val_tk := TK_INTEGER;
          IF IsUnsignedWordTk(last_val_tk) THEN
            res := LLVMConstInt(LLVMTypeForTk(last_val_tk), const_tbl[consti].ival, 0)
          ELSE
            res := LLVMConstInt(LLVMTypeForTk(last_val_tk), const_tbl[consti].ival, 1);
        END;
      END
      ELSE IF RoutineIsFunc(routi) THEN
        { A zero-arg FUNCTION called without parens (e.g. `getchar`,
          `cJSON_CreateObject` -- common for [C] EXTERN declarations):
          Identifier and a bare FuncCall are the same AST shape here, so
          fall through to the shared call path instead of treating it as an
          undefined variable. }
        res := CodegenCallCommon(nm, NIL)
      ELSE
      BEGIN
        AbortWith2('codegen: undefined variable: ', nm);
        res := NIL;
      END;
    END;
    END;
  END
  ELSE IF (nt = 'Designator') OR (nt = 'PostfixExpr') THEN  BEGIN
    { A zero-selector designator is a direct read: check it, or propagate
      its state when unchecked (GuardInitckRead handles both). }
    IF (nt = 'Designator') AND (ArrSize(GetObj(node, 'selectors')) = 0) THEN
    BEGIN
      symi := LookupSym(GetStr(node, 'name'));
      IF symi <> 0 THEN GuardInitckRead(node, symi);
    END;
    addr := ComputeDesignatorAddress(node);
    result_tid := last_val_tk;
    value_shadow := last_desig_shadow;
    { A selected tracked component is checked (or propagated) after its
      index operands and bounds checks, before the native load below. }
    IF (nt = 'PostfixExpr') OR (ArrSize(GetObj(node, 'selectors')) <> 0) THEN
    BEGIN
      IF value_shadow <> NIL THEN
        GuardInitckComponent(node, value_shadow, result_tid)
      ELSE IF GetBool(GetObj(node, 'read_flags'), 'INITCK') THEN
        InitckBoundaryAt('selected storage', node);
    END;
    res := LLVMBuildLoad2(builder, LLVMTypeForTk(result_tid), addr, MakeCStr(''));
    last_val_tk := result_tid;
  END
  ELSE IF nt = 'StringLiteral' THEN
  BEGIN
    res := LLVMBuildGlobalStringPtr(builder, MakeCStr(DecodeStringLiteral(GetStr(node, 'value'))), MakeCStr('str'));
    last_val_tk := TK_ADRMEM;
  END
  ELSE IF nt = 'SizeofExpr' THEN
  BEGIN
    target_item := GetObj(node, 'target');
    target_str := cJSON_GetStringValue(target_item);
    IF target_str <> NIL THEN
    BEGIN
      nm := GetStr(node, 'target');
      symi := LookupSym(nm);
      IF symi <> 0 THEN
        sizeof_bytes := TypeSizeBytes(symbols[symi].tk)
      ELSE
      BEGIN
        sizeof_synth := CreateNode('NamedType');
        AddStringField(sizeof_synth, 'name', nm);
        AddNullField(sizeof_synth, 'param');
        sizeof_bytes := TypeSizeBytes(ResolveTypeExpr(sizeof_synth));
      END;
    END
    ELSE
      sizeof_bytes := TypeSizeBytes(ResolveTypeExpr(target_item));
    res := LLVMConstInt(i16ty, sizeof_bytes, 0);
    last_val_tk := TK_WORD;
  END
  ELSE IF nt = 'BinOp' THEN
    res := CodegenBinOp(GetStr(node, 'op'), GetObj(node, 'left'), GetObj(node, 'right'), node)
  ELSE IF nt = 'SetConstructor' THEN
    res := CodegenSetConstructor(node)
  ELSE IF nt = 'UnaryOp' THEN
    res := CodegenUnaryOp(GetStr(node, 'op'), GetObj(node, 'operand'), node)
  ELSE IF (nt = 'UpperExpr') OR (nt = 'LowerExpr') THEN
  BEGIN
    { Type-only walk for static bounds; only a final dereference of a
      SUPER ARRAY pointer needs its selected allocation at run time. }
    bound_operand := GetObj(node, 'operand');
    bound_sels := GetObj(bound_operand, 'selectors');
    bound_n := ArrSize(bound_sels);
    result_tid := BoundOperandType(bound_operand);
    bound_is_subrange := FALSE;
    IF result_tid >= 14 THEN
      bound_is_subrange := types[result_tid].is_subrange;
    IF result_tid = TK_UNKNOWN THEN
      AbortWith('codegen: invalid UPPER/LOWER designator');
    { ArrItem is only called on a nonempty selector list. }
    IF bound_n > 0 THEN
      nm := GetStr(ArrItem(bound_sels, bound_n - 1), 'kind')
    ELSE
      nm := '';
    IF nm = 'DEREF' THEN
    BEGIN
      IF (TypeKind(result_tid) <> TK_ARRAY) OR (NOT types[result_tid].is_super) THEN
        AbortWith('codegen: UPPER/LOWER dereference requires a SUPER ARRAY pointer');
      IF nt = 'LowerExpr' THEN
        res := LLVMConstInt(i64ty, types[result_tid].lo, 1)
      ELSE
      BEGIN
        super_ptr := ComputeDesignatorAddress(bound_operand);
        super_ptr := LLVMBuildBitCast(builder, super_ptr, i8ptrty, MakeCStr(''));
        nil_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('upper.nil'));
        ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('upper.ok'));
        is_nil := LLVMBuildICmp(builder, LLVMIntEQ, super_ptr,
          LLVMConstPointerNull(i8ptrty), MakeCStr(''));
        LLVMBuildCondBr(builder, is_nil, nil_bb, ok_bb);
        LLVMPositionBuilderAtEnd(builder, nil_bb);
        err_args := MakeArgs1(LLVMConstInt(i32ty, 0, 0));
        nil_fnty := LLVMFunctionType(voidty, MakeArgs1(i32ty), 1, 0);
        nil_fn := LLVMGetNamedFunction(modl, MakeCStr('pas_upper_nil_error'));
        IF nil_fn = NIL THEN
          nil_fn := LLVMAddFunction(modl, MakeCStr('pas_upper_nil_error'), nil_fnty);
        discard := LLVMBuildCall2(builder, nil_fnty, nil_fn, err_args, 1, MakeCStr(''));
        discard := LLVMBuildUnreachable(builder);
        LLVMPositionBuilderAtEnd(builder, ok_bb);
        IF is_device_compiland THEN
        BEGIN
          { Preserve legacy DEVICE lowering; it is not a host descriptor. }
          super_header := LLVMBuildGEP2(builder, i8ty, super_ptr,
            MakeArgs1(LLVMConstInt(i64ty, -8, 1)), 1, MakeCStr(''));
          res := LLVMBuildLoad2(builder, i64ty, super_header, MakeCStr(''));
        END
        ELSE
        BEGIN
          IF last_desig_super_upper = NIL THEN
            AbortWith('codegen: UPPER super-array pointer has no host descriptor bound');
          res := last_desig_super_upper;
        END;
      END;
      last_val_tk := TK_INTEGER64;
    END
    ELSE BEGIN
      IF TypeKind(result_tid) = TK_ARRAY THEN
        IF types[result_tid].is_super THEN
          AbortWith('codegen: non-pointer SUPER ARRAY value has no runtime bound');
      IF (TypeKind(result_tid) = TK_ARRAY) OR (TypeKind(result_tid) = TK_STRING)
         OR (TypeKind(result_tid) = TK_LSTRING) OR (TypeKind(result_tid) = TK_VECTOR)
         OR (TypeKind(result_tid) = TK_SET) OR (TypeKind(result_tid) = TK_ENUM)
         OR bound_is_subrange THEN
      BEGIN
        static_bound_tid := TK_INTEGER;
        IF TypeKind(result_tid) = TK_SET THEN
          static_bound_tid := types[result_tid].elem_tid
        ELSE IF TypeKind(result_tid) = TK_ARRAY THEN
          static_bound_tid := types[result_tid].index_tid
        ELSE IF (TypeKind(result_tid) = TK_ENUM) OR bound_is_subrange THEN
          static_bound_tid := result_tid;
        IF nt = 'UpperExpr' THEN
          res := LLVMConstInt(LLVMTypeForTk(static_bound_tid), types[result_tid].hi, 1)
        ELSE
          res := LLVMConstInt(LLVMTypeForTk(static_bound_tid), types[result_tid].lo, 1);
      END
      ELSE BEGIN
        AbortWith('codegen: UPPER/LOWER requires an array, set, enum or subrange expression');
        res := NIL;
        static_bound_tid := TK_UNKNOWN;
      END;
      last_val_tk := static_bound_tid;
    END;
  END
  ELSE IF nt = 'RetypeExpr' THEN
  BEGIN
    { RETYPE(TypeName, expr): the explicit reinterpret-cast builtin used
      throughout the self-hosting sources for otherwise-implicit-narrowing
      integer conversions the type system disallows implicitly (e.g.
      INTEGER32/INTEGER64 -> INTEGER). Every self-hosting use is a plain
      scalar integer-family narrow/widen -- aggregate/pointer reinterpret
      (the reference codegen's fuller RetypeExpr handling in
      codegen/exprs.py) is not needed here, so only that case is
      implemented; anything else aborts with a clear diagnostic rather than
      emitting something wrong. }
    IF ArrSize(GetObj(node, 'selectors')) > 0 THEN
    BEGIN
      AbortWith2('codegen: RETYPE with selectors not supported', '');
      res := NIL;
    END
    ELSE
    BEGIN
      res := CodegenExpr(GetObj(node, 'expr'));
      result_tid := LookupNamedType(GetStr(node, 'type_id'));
      IF IsHostDescriptor(last_val_tk) OR IsHostDescriptor(result_tid) THEN
        AbortWith('codegen: RETYPE cannot convert super-array descriptors; use explicit unsafe conversion');
      result_tid := TypeNameStrToTk(GetStr(node, 'type_id'));
      IF IsIntegerFamilyTk(last_val_tk) AND IsIntegerFamilyTk(result_tid) THEN
      BEGIN
        IF IntFamilyWidth(last_val_tk) > IntFamilyWidth(result_tid) THEN
          res := LLVMBuildTrunc(builder, res, LLVMTypeForTk(result_tid), MakeCStr(''))
        ELSE IF IntFamilyWidth(last_val_tk) < IntFamilyWidth(result_tid) THEN
        BEGIN
          IF IsUnsignedWordTk(last_val_tk) THEN
            res := LLVMBuildZExt(builder, res, LLVMTypeForTk(result_tid), MakeCStr(''))
          ELSE
            res := LLVMBuildSExt(builder, res, LLVMTypeForTk(result_tid), MakeCStr(''));
        END;
        last_val_tk := result_tid;
      END
      ELSE
      BEGIN
        AbortWith2('codegen: RETYPE not supported for this type combination: ', GetStr(node, 'type_id'));
      END;
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    nm_raw := GetStr(node, 'name');
    nm := UpperStr(nm_raw);
    IF UserRoutineShadows(nm_raw) THEN
    BEGIN
      symi := LookupRoutine(nm_raw);
      IF NOT routines[symi].is_func THEN
      BEGIN
        AbortWith2('codegen: called as a function but is a PROCEDURE: ', nm_raw);
        res := NIL;
      END
      ELSE IF is_nvptx_device AND IsDeviceUnsupportedTranscendental(nm_raw)
              AND NOT routines[symi].has_body
              AND NOT routines[symi].is_forward THEN
      BEGIN
        { A body-less declaration is an EXTERN libm import.  Emitting it
          would leave an unresolved transcendental call in PTX; a user
          routine with a body remains callable.  A FORWARD placeholder is
          neither: its body arrives later in this same compiland, so
          has_body is still FALSE at every call sited between the header and
          the definition -- rejecting those would contradict the shadowing
          rule docs/dialect_notes.md states. }
        AbortWith2('codegen: transcendental math function is not supported in DEVICE code: ', nm_raw);
        res := NIL;
      END
      ELSE
        res := CodegenCallCommon(nm_raw, GetObj(node, 'args'));
    END
    ELSE IF nm = 'POSITN' THEN
    BEGIN
      res := CodegenPositn(GetObj(node, 'args'));
      last_val_tk := TK_INTEGER;
    END
    ELSE IF nm = 'SCANEQ' THEN
    BEGIN
      res := CodegenScan(1, GetObj(node, 'args'));
      last_val_tk := TK_INTEGER;
    END
    ELSE IF nm = 'SCANNE' THEN
    BEGIN
      res := CodegenScan(0, GetObj(node, 'args'));
      last_val_tk := TK_INTEGER;
    END
    ELSE IF nm = 'ENCODE' THEN
    BEGIN
      res := CodegenEncode(GetObj(node, 'args'));
      last_val_tk := TK_BOOLEAN;
    END
    ELSE IF (nm = 'SADDOK') OR (nm = 'SMULOK') OR (nm = 'UADDOK') OR (nm = 'UMULOK') THEN
      res := CodegenOverflowOk(nm, GetObj(node, 'args'))
    ELSE IF nm = 'DECODE' THEN
    BEGIN
      res := CodegenDecode(GetObj(node, 'args'));
      last_val_tk := TK_BOOLEAN;
    END
    ELSE IF (nm = 'CHR') OR (nm = 'ORD') OR (nm = 'ODD') OR (nm = 'SUCC') OR (nm = 'PRED')
      OR (nm = 'ABS') OR (nm = 'SQR') OR (nm = 'SQRT') OR (nm = 'SIN') OR (nm = 'COS')
      OR (nm = 'LN') OR (nm = 'EXP') OR (nm = 'ARCTAN') OR (nm = 'TRUNC') OR (nm = 'ROUND')
      OR (nm = 'FLOAT') OR (nm = 'HIBYTE') OR (nm = 'LOBYTE') OR (nm = 'WRD') OR (nm = 'WRD8') OR (nm = 'BYWORD') THEN
      res := CodegenSimpleBuiltin(nm, node)
    ELSE IF (nm = 'UNSAFERAW') OR (nm = 'UNSAFESUPER') THEN
    BEGIN
      IF NOT FeaturesAreExtended(active_features) THEN
        AbortWith('codegen: unsafe super-array conversions require the extended dialect');
      IF is_device_compiland THEN
        AbortWith('codegen: unsafe super-array conversions are not permitted in DEVICE code');
      IF nm = 'UNSAFESUPER' THEN res := CodegenUnsafeSuper(GetObj(node, 'args'))
      ELSE
      BEGIN
        call_args := GetObj(node, 'args');
        IF ArrSize(call_args) <> 1 THEN AbortWith('codegen: UNSAFERAW expects one descriptor pointer argument');
        res := CodegenExpr(ArrItem(call_args, 0));
        IF NOT IsHostDescriptor(last_val_tk) THEN
          AbortWith('codegen: UNSAFERAW requires a host super-array descriptor pointer');
        res := LLVMBuildExtractValue(builder, res, 0, MakeCStr(''));
        { The exported elements leave the INITCK model. }
        InitckHeapRelease(res);
        last_val_tk := TK_ADRMEM;
      END;
      EPrint('warning: unsafe-super-array-conversion');
    END
    ELSE IF nm = 'DEVALLOC' THEN
      res := CodegenDevAlloc(GetObj(node, 'args'))
    ELSE IF nm = 'VSPLAT' THEN
    BEGIN
      { VSPLAT(x, V): the second argument is a VECTOR type NAME, not a
        value -- it parses as a bare Identifier and is resolved against the
        named-type table here (the typechecker's VSPLAT rule mirrors this).
        A new pattern for this dialect: no other builtin takes a type name. }
      call_args := GetObj(node, 'args');
      IF ArrSize(call_args) <> 2 THEN
        AbortWith('codegen: VSPLAT expects (scalar, VECTOR type name)');
      IF NodeType(ArrItem(call_args, 1)) <> 'Identifier' THEN
        AbortWith('codegen: VSPLAT second argument must be a VECTOR type name');
      result_tid := LookupNamedType(GetStr(ArrItem(call_args, 1), 'name'));
      IF (result_tid = 0) OR (TypeKind(result_tid) <> TK_VECTOR) THEN
        AbortWith2('codegen: VSPLAT type argument is not a VECTOR type: ', GetStr(ArrItem(call_args, 1), 'name'));
      res := CodegenExpr(ArrItem(call_args, 0));
      res := CodegenVSplat(res, last_val_tk, result_tid, ArrItem(call_args, 0));
      last_val_tk := result_tid;
    END
    ELSE IF (nm = 'VSUM') OR (nm = 'VPROD') OR (nm = 'VMIN') OR (nm = 'VMAX')
         OR (nm = 'VANY') OR (nm = 'VALL') THEN
    BEGIN
      { Horizontal reduction: one VECTOR argument -> a scalar. CodegenVReduce
        emits the llvm.vector.reduce.* intrinsic and sets last_val_tk. }
      call_args := GetObj(node, 'args');
      IF ArrSize(call_args) <> 1 THEN
        AbortWith2('codegen: reduction takes exactly one VECTOR argument: ', nm);
      res := CodegenExpr(ArrItem(call_args, 0));
      IF TypeKind(last_val_tk) <> TK_VECTOR THEN
        AbortWith2('codegen: reduction argument is not a VECTOR: ', nm);
      IF ((nm = 'VSUM') OR (nm = 'VPROD')) AND
         IsIntegerFamilyTk(types[last_val_tk].elem_tid) AND SiteMathCk(node) THEN
        res := CodegenCheckedVReduce(nm, res, last_val_tk, node)
      ELSE
        res := CodegenVReduce(nm, res, last_val_tk);
    END
    ELSE IF nm = 'VSELECT' THEN
    BEGIN
      { VSELECT(m, a, b): lanewise pick. m is a VECTOR OF BOOLEAN mask,
        a and b the same VECTOR type; result is that type. }
      call_args := GetObj(node, 'args');
      IF ArrSize(call_args) <> 3 THEN
        AbortWith('codegen: VSELECT expects (mask, a, b)');
      vsel_mask := CodegenExpr(ArrItem(call_args, 0));
      vsel_mask_tid := last_val_tk;
      vsel_a := CodegenExpr(ArrItem(call_args, 1));
      vsel_a_tid := last_val_tk;
      vsel_b := CodegenExpr(ArrItem(call_args, 2));
      vsel_b_tid := last_val_tk;
      res := CodegenVSelect(vsel_mask, vsel_a, vsel_b,
                            vsel_mask_tid, vsel_a_tid, vsel_b_tid);
      last_val_tk := vsel_a_tid;
    END
    ELSE IF nm = 'VLOAD' THEN
    BEGIN
      { VLOAD(arr, i, V): load arr[i .. i+n-1] as a V vector. arr is an
        array variable or designator (see VectorArrayOperand); V is a VECTOR type NAME (a bare Identifier, resolved
        against the type table -- the same new pattern as VSPLAT). }
      call_args := GetObj(node, 'args');
      IF ArrSize(call_args) <> 3 THEN
        AbortWith('codegen: VLOAD expects (array, index, VECTOR type name)');
      IF NodeType(ArrItem(call_args, 2)) <> 'Identifier' THEN
        AbortWith('codegen: VLOAD third argument must be a VECTOR type name');
      result_tid := LookupNamedType(GetStr(ArrItem(call_args, 2), 'name'));
      IF (result_tid = 0) OR (TypeKind(result_tid) <> TK_VECTOR) THEN
        AbortWith2('codegen: VLOAD type argument is not a VECTOR type: ', GetStr(ArrItem(call_args, 2), 'name'));
      { Evaluation order: array address, then index, then the check. }
      vld_arr := VectorArrayOperand(ArrItem(call_args, 0), vld_arr_tid, vld_hdr);
      vld_idx := CodegenExpr(ArrItem(call_args, 1));
      vld_idx_tk := last_val_tk;
      res := CodegenVLoad(vld_arr, vld_arr_tid,
                          vld_idx, vld_idx_tk, result_tid, ArrItem(call_args, 1),
                          vld_hdr);
      last_val_tk := result_tid;
    END
    ELSE IF (nm = 'EOF') OR (nm = 'EOLN') THEN
    BEGIN
      call_args := AllocPtrArray(1);
      SetPtrArrayElem(call_args, 0, LoadFileFcbPtr(GetStr(ArrItem(GetObj(node, 'args'), 0), 'name')));
      IF nm = 'EOF' THEN
        res := LLVMBuildCall2(builder, file_eof_fnty, file_eof_fn, call_args, 1, MakeCStr(''))
      ELSE
        res := LLVMBuildCall2(builder, file_eoln_fnty, file_eoln_fn, call_args, 1, MakeCStr(''));
      res := LLVMBuildICmp(builder, LLVMIntNE, res, LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
      last_val_tk := TK_BOOLEAN;
    END
    ELSE
    BEGIN
      AbortWith2('codegen: undefined function: ', nm_raw);
      res := NIL;
    END;
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unhandled expression kind: ', nt);
    res := NIL;
  END;
  cur_rangeck := saved_rangeck;
  LeaveExprLevel;
  last_val_tk := SubrangeBaseTid(last_val_tk);
  last_value_shadow := value_shadow;
  CodegenExpr := res;
END;

{ ---- string/builtin helpers shared with statement lowering ---- }

PROCEDURE ResolveStringExprCharsLen(expr: ADRMEM; VAR chars_ptr: ADRMEM; VAR len_val: ADRMEM);
{ The counterpart of the Python reference's get_string_chars_and_len: given
  a CONST STRING-typed actual argument (a string literal, or an Identifier
  naming an LSTRING/STRING variable), returns a pointer to its first
  character plus its length as an i32 -- LSTRING's is the dynamic runtime
  length byte, STRING's is its fixed declared capacity. Scoped to what
  CONCAT/COPYLST/COPYSTR need; a designator (indexed/field string
  sub-expression) is not yet supported here. }
VAR
  strval: Str255;
  symi: INTEGER32;
  tid: INTEGER;
  addr, gep_idx, len_ptr: ADRMEM;
BEGIN
  IF NodeType(expr) = 'StringLiteral' THEN
  BEGIN
    strval := DecodeStringLiteral(GetStr(expr, 'value'));
    chars_ptr := LLVMBuildGlobalStringPtr(builder, MakeCStr(strval), MakeCStr('str'));
    len_val := LLVMConstInt(i32ty, ORD(strval[0]), 0);
  END
  ELSE IF NodeType(expr) = 'Identifier' THEN
  BEGIN
    symi := LookupSym(GetStr(expr, 'name'));
    IF (symi = 0) AND RoutineIsFunc(LookupRoutine(GetStr(expr, 'name'))) THEN
    BEGIN
      { A bare niladic-call Identifier (e.g. `CurKind = 'LBRACKET'`, an
        aggregate Str255-returning FUNCTION called without parens) has no
        symbol-table entry of its own -- materialize the call's result
        into a fresh temporary, same as ComputeDesignatorAddress and
        CodegenCallCommon's VAR-argument marshaling do for the same shape. }
      tid := routines[LookupRoutine(GetStr(expr, 'name'))].ret_tk;
      addr := EntryAlloca(LLVMTypeForTk(tid), '');
      LLVMBuildStore(builder, CodegenCallCommon(GetStr(expr, 'name'), NIL), addr);
    END
    ELSE
    BEGIN
      IF symi = 0 THEN
        AbortWith2('codegen: undefined variable: ', GetStr(expr, 'name'));
      tid := symbols[symi].tk;
      addr := symbols[symi].llvm_val;
    END;
    IF TypeKind(tid) = TK_LSTRING THEN
    BEGIN
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
      len_val := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
      len_val := LLVMBuildZExt(builder, len_val, i32ty, MakeCStr(''));
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith2('codegen: not a string-typed variable: ', GetStr(expr, 'name'));
      chars_ptr := NIL;
      len_val := NIL;
    END;
  END
  ELSE IF NodeType(expr) = 'FuncCall' THEN
  BEGIN
    { An aggregate Str255-returning FUNCTION called with explicit args (e.g.
      `NodeType(expr) = 'Identifier'`, pervasive throughout this file and
      typechecker.pas) -- materialize the call's result into a fresh
      temporary, same idiom as the bare-niladic-Identifier branch above. }
    tid := routines[LookupRoutine(GetStr(expr, 'name'))].ret_tk;
    addr := EntryAlloca(LLVMTypeForTk(tid), '');
    LLVMBuildStore(builder, CodegenCallCommon(GetStr(expr, 'name'), GetObj(expr, 'args')), addr);
    IF TypeKind(tid) = TK_LSTRING THEN
    BEGIN
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
      len_val := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
      len_val := LLVMBuildZExt(builder, len_val, i32ty, MakeCStr(''));
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith2('codegen: not a string-returning function call: ', GetStr(expr, 'name'));
      chars_ptr := NIL;
      len_val := NIL;
    END;
  END
  ELSE IF NodeType(expr) = 'Designator' THEN
  BEGIN
    addr := ComputeDesignatorAddress(expr);
    tid := last_val_tk;
    IF TypeKind(tid) = TK_LSTRING THEN
    BEGIN
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
      len_val := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
      len_val := LLVMBuildZExt(builder, len_val, i32ty, MakeCStr(''));
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith('codegen: not a string-typed designator expression');
      chars_ptr := NIL;
      len_val := NIL;
    END;
  END
  ELSE
  BEGIN
    AbortWith('codegen: unsupported string expression (only literals and bare variables are supported)');
    chars_ptr := NIL;
    len_val := NIL;
  END;
END;

PROCEDURE ResolveStringDestVar(expr: ADRMEM; VAR d_symi: INTEGER32; VAR d_tid: INTEGER;
  VAR d_addr, chars_ptr, len_val: ADRMEM);
{ The mutable-destination counterpart of ResolveStringExprCharsLen, for
  INSERT/DELETE, which need the destination's own symbol/address (to write
  a new length byte back afterward) as well as its current chars/length.
  Scoped to a bare Identifier naming an LSTRING or STRING variable, same as
  every other string-builtin destination in this file. }
VAR
  gep_idx, len_ptr: ADRMEM;
BEGIN
  IF NodeType(expr) <> 'Identifier' THEN
    AbortWith('codegen: a string builtin''s destination must be a bare LSTRING/STRING variable');
  d_symi := LookupSym(GetStr(expr, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(expr, 'name'));
  d_tid := symbols[d_symi].tk;
  d_addr := symbols[d_symi].llvm_val;
  IF TypeKind(d_tid) = TK_LSTRING THEN
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
    len_val := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
    len_val := LLVMBuildZExt(builder, len_val, i32ty, MakeCStr(''));
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
    chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  END
  ELSE IF TypeKind(d_tid) = TK_STRING THEN
  BEGIN
    len_val := LLVMConstInt(i32ty, types[d_tid].hi, 0);
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  END
  ELSE
  BEGIN
    AbortWith2('codegen: not an LSTRING/STRING variable: ', GetStr(expr, 'name'));
    chars_ptr := NIL;
    len_val := NIL;
  END;
END;

FUNCTION CodegenPositn(args: ADRMEM): ADRMEM;
{ POSITN(hay, needle): INTEGER -- 1-based index of the first occurrence of
  `needle` within `hay`, or 0 if absent; the search itself is entirely
  libpascalrt's runtime `positn` (positn.c), called exactly like printf. }
VAR
  hay_chars, hay_len, needle_chars, needle_len: ADRMEM;
  call_args, res32: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: POSITN expects exactly 2 arguments');
  ResolveStringExprCharsLen(ArrItem(args, 0), hay_chars, hay_len);
  ResolveStringExprCharsLen(ArrItem(args, 1), needle_chars, needle_len);
  call_args := AllocPtrArray(4);
  SetPtrArrayElem(call_args, 0, hay_chars);
  SetPtrArrayElem(call_args, 1, hay_len);
  SetPtrArrayElem(call_args, 2, needle_chars);
  SetPtrArrayElem(call_args, 3, needle_len);
  res32 := LLVMBuildCall2(builder, positn_fnty, positn_fn, call_args, 4, MakeCStr(''));
  CodegenPositn := LLVMBuildTrunc(builder, res32, i16ty, MakeCStr(''));
END;

FUNCTION CodegenScan(stop_on_equal: INTEGER; args: ADRMEM): ADRMEM;
{ SCANEQ(L, P, S, I) / SCANNE(L, P, S, I): INTEGER -- returns the
  signed number of characters skipped, or L if no stopping character is
  found. Negative L scans backward; I is a 1-based position. }
VAR
  l_val, p_val, s_chars, s_len, i_val: ADRMEM;
  call_args, res32: ADRMEM;
BEGIN
  IF ArrSize(args) <> 4 THEN
    AbortWith('codegen: SCANEQ/SCANNE expects exactly 4 arguments');
  l_val := CodegenExpr(ArrItem(args, 0));
  l_val := CoerceForAssign(l_val, last_val_tk, TK_INTEGER, ArrItem(args, 0), 'SCANEQ/SCANNE');
  l_val := LLVMBuildSExt(builder, l_val, i32ty, MakeCStr(''));
  p_val := CodegenExpr(ArrItem(args, 1));
  IF last_val_tk <> TK_CHAR THEN
    AbortWith('codegen: SCANEQ/SCANNE''s P argument must be CHAR');
  { Strings have no INITCK shadow representation yet. Do not expose a
    newly reachable unchecked length/data read at an enabled read site. }
  IF NodeType(ArrItem(args, 2)) <> 'StringLiteral' THEN
    IF GetBool(GetObjOrNil(ArrItem(args, 2), 'read_flags'), 'INITCK') THEN
      InitckBoundaryAt('STRING/LSTRING scan source', ArrItem(args, 2));
  ResolveStringExprCharsLen(ArrItem(args, 2), s_chars, s_len);
  i_val := CodegenExpr(ArrItem(args, 3));
  i_val := CoerceForAssign(i_val, last_val_tk, TK_INTEGER, ArrItem(args, 3), 'SCANEQ/SCANNE');
  i_val := LLVMBuildSExt(builder, i_val, i32ty, MakeCStr(''));

  call_args := AllocPtrArray(6);
  SetPtrArrayElem(call_args, 0, l_val);
  SetPtrArrayElem(call_args, 1, p_val);
  SetPtrArrayElem(call_args, 2, s_chars);
  SetPtrArrayElem(call_args, 3, s_len);
  SetPtrArrayElem(call_args, 4, i_val);
  SetPtrArrayElem(call_args, 5, LLVMConstInt(i32ty, stop_on_equal, 0));
  IF stop_on_equal <> 0 THEN
    res32 := LLVMBuildCall2(builder, scaneq_fnty, scaneq_fn, call_args, 6, MakeCStr(''))
  ELSE
    res32 := LLVMBuildCall2(builder, scanne_fnty, scanne_fn, call_args, 6, MakeCStr(''));
  CodegenScan := LLVMBuildTrunc(builder, res32, i16ty, MakeCStr(''));
END;

FUNCTION CodegenEncode(args: ADRMEM): ADRMEM;
{ ENCODE(VAR D: LSTRING; value: INTEGER): BOOLEAN -- formats `value` as
  decimal text into D via libpascalrt's runtime `encode_value`
  (encode_decode.c), which also sets D's length-prefix byte on success.
  WRITE-style `value:width` is supported (the width becomes encode_value's
  minimum field width); `:precision` is accepted syntactically but ignored,
  matching the runtime (REAL formatting is not implemented there either).
  Scoped to an LSTRING destination and an INTEGER value, matching every
  test/usage this file has verified against; the reference's own signature
  is looser (dest could in principle be any string kind) but ENCODE always
  needs to write a length-prefix byte in every real usage, so LSTRING-only
  is not a meaningful narrowing in practice. }
VAR
  dest_expr, value_expr: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, dest_chars, dest_len_unused: ADRMEM;
  val, width_val: ADRMEM;
  call_args: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: ENCODE expects exactly 2 arguments');
  dest_expr := GetObj(ArrItem(args, 0), 'expr');
  ResolveStringDestVar(dest_expr, d_symi, d_tid, d_addr, dest_chars, dest_len_unused);
  IF TypeKind(d_tid) <> TK_LSTRING THEN
    AbortWith('codegen: ENCODE''s destination must be an LSTRING variable');

  value_expr := GetObj(ArrItem(args, 1), 'expr');
  val := CodegenExpr(value_expr);
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: ENCODE''s value argument must be INTEGER');
  val := LLVMBuildSExt(builder, val, i32ty, MakeCStr(''));

  IF GetObjOrNil(ArrItem(args, 1), 'width') <> NIL THEN
  BEGIN
    width_val := CodegenExpr(GetObj(ArrItem(args, 1), 'width'));
    IF last_val_tk <> TK_INTEGER THEN
      AbortWith('codegen: ENCODE''s width argument must be INTEGER');
    width_val := LLVMBuildSExt(builder, width_val, i32ty, MakeCStr(''));
  END
  ELSE
    width_val := LLVMConstInt(i32ty, 0, 0);

  call_args := AllocPtrArray(7);
  SetPtrArrayElem(call_args, 0, dest_chars);
  SetPtrArrayElem(call_args, 1, LLVMConstInt(i32ty, types[d_tid].hi, 0));
  SetPtrArrayElem(call_args, 2, LLVMBuildBitCast(builder, d_addr, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(call_args, 3, val);
  SetPtrArrayElem(call_args, 4, width_val);
  SetPtrArrayElem(call_args, 5, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(call_args, 6, LLVMConstInt(i32ty, 0, 0));
  CodegenEncode := LLVMBuildICmp(builder, LLVMIntNE,
    LLVMBuildCall2(builder, encode_fnty, encode_fn, call_args, 7, MakeCStr('')),
    LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
END;

FUNCTION CodegenOverflowOk(nm: Str255; args: ADRMEM): ADRMEM;
{ The IBM library functions SADDOK/SMULOK (INTEGER) and UADDOK/UMULOK
  (WORD), manual 11-21: store the 16-bit sum or product, wrapped, through
  VAR C and return TRUE when it did not overflow. They never trap,
  whatever MATHCK says. Reached only when no user declaration of the name
  is visible. }
VAR
  tk: INTEGER;
  a, b, c_node, c_addr, pair: ADRMEM;
  symi: INTEGER32;
  op: Str255;
BEGIN
  IF ArrSize(args) <> 3 THEN AbortWith2('codegen: expects (A, B, VAR C): ', nm);
  IF (nm = 'SADDOK') OR (nm = 'SMULOK') THEN tk := TK_INTEGER ELSE tk := TK_WORD;
  IF (nm = 'SADDOK') OR (nm = 'UADDOK') THEN op := 'PLUS' ELSE op := 'MUL';
  a := CodegenExpr(ArrItem(args, 0));
  a := CoerceForAssign(a, last_val_tk, tk, ArrItem(args, 0), nm);
  b := CodegenExpr(ArrItem(args, 1));
  b := CoerceForAssign(b, last_val_tk, tk, ArrItem(args, 1), nm);
  c_node := ArrItem(args, 2);
  c_addr := NIL;
  IF NodeType(c_node) = 'Identifier' THEN
  BEGIN
    symi := LookupSym(GetStr(c_node, 'name'));
    IF symi = 0 THEN AbortWith2('codegen: undefined variable: ', GetStr(c_node, 'name'));
    IF symbols[symi].tk <> tk THEN AbortWith2('codegen: VAR argument type mismatch calling: ', nm);
    c_addr := symbols[symi].llvm_val;
  END
  ELSE IF NodeType(c_node) = 'Designator' THEN
  BEGIN
    c_addr := ComputeDesignatorAddress(c_node);
    IF last_val_tk <> tk THEN AbortWith2('codegen: VAR argument type mismatch calling: ', nm);
  END
  ELSE
    AbortWith2('codegen: a VAR argument must be an lvalue, calling: ', nm);
  pair := OverflowIntrinsicCall(op, a, b, tk);
  LLVMBuildStore(builder, LLVMBuildExtractValue(builder, pair, 0, MakeCStr('')), c_addr);
  last_val_tk := TK_BOOLEAN;
  CodegenOverflowOk := LLVMBuildNot(builder,
    LLVMBuildExtractValue(builder, pair, 1, MakeCStr('')), MakeCStr(''));
END;

FUNCTION CodegenDecode(args: ADRMEM): ADRMEM;
{ DECODE(src: STRING-or-LSTRING-or-literal; VAR dest: INTEGER-or-CHAR):
  BOOLEAN -- parses a decimal integer out of `src` and stores it into
  `dest`, via libpascalrt's runtime `decode_value`. dest_size (the write's
  byte width) is derived from dest's own declared scalar type -- scoped to
  INTEGER (2 bytes) and CHAR (1 byte), the two dest_size cases
  decode_value's own manual documents by name; anything else is rejected
  rather than guessing a width. }
VAR
  src_expr, dest_expr: ADRMEM;
  src_chars, src_len: ADRMEM;
  d_symi: INTEGER32;
  d_addr: ADRMEM;
  dest_size: INTEGER;
  call_args: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: DECODE expects exactly 2 arguments');
  src_expr := GetObj(ArrItem(args, 0), 'expr');
  ResolveStringExprCharsLen(src_expr, src_chars, src_len);

  dest_expr := GetObj(ArrItem(args, 1), 'expr');
  IF NodeType(dest_expr) <> 'Identifier' THEN
    AbortWith('codegen: DECODE''s destination must be a bare INTEGER/CHAR variable');
  d_symi := LookupSym(GetStr(dest_expr, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(dest_expr, 'name'));
  d_addr := symbols[d_symi].llvm_val;
  IF symbols[d_symi].tk = TK_INTEGER THEN dest_size := 2
  ELSE IF symbols[d_symi].tk = TK_CHAR THEN dest_size := 1
  ELSE
  BEGIN
    AbortWith('codegen: DECODE''s destination must be INTEGER or CHAR');
    dest_size := 0;
  END;

  call_args := AllocPtrArray(7);
  SetPtrArrayElem(call_args, 0, src_chars);
  SetPtrArrayElem(call_args, 1, src_len);
  SetPtrArrayElem(call_args, 2, LLVMBuildBitCast(builder, d_addr, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(call_args, 3, LLVMConstInt(i32ty, dest_size, 0));
  SetPtrArrayElem(call_args, 4, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(call_args, 5, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(call_args, 6, LLVMConstInt(i32ty, 0, 0));
  CodegenDecode := LLVMBuildICmp(builder, LLVMIntNE,
    LLVMBuildCall2(builder, decode_fnty, decode_fn, call_args, 7, MakeCStr('')),
    LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
END;

BEGIN
END.
