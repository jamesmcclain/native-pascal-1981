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

PROCEDURE EmitSetRangeLoop(slot: ADRMEM; low_node, high_node: ADRMEM);
{ FOR i := low TO high DO SetRuntimeBit(slot, i) -- same alloca-counter loop
  idiom as CodegenForStmt/EmitByteCopyLoop, done here instead of reusing
  CodegenForStmt directly since there is no surface-syntax FOR loop AST node
  to hand it (RangeExpr's bounds are arbitrary INTEGER expressions, not
  necessarily a declared loop variable). A reversed range (low > high) is
  simply empty, exactly like the Python reference. }
VAR
  low_val, high_val: ADRMEM;
  i_slot: ADRMEM;
  loop_bb, body_bb, end_bb: ADRMEM;
  cur_i, cmp_val, next_i: ADRMEM;
BEGIN
  low_val := CodegenExpr(low_node);
  IF last_val_tk = TK_CHAR THEN low_val := LLVMBuildZExt(builder, low_val, i16ty, MakeCStr(''))
  ELSE IF last_val_tk <> TK_INTEGER THEN AbortWith('codegen: a set range bound must be INTEGER or CHAR');
  high_val := CodegenExpr(high_node);
  IF last_val_tk = TK_CHAR THEN high_val := LLVMBuildZExt(builder, high_val, i16ty, MakeCStr(''))
  ELSE IF last_val_tk <> TK_INTEGER THEN AbortWith('codegen: a set range bound must be INTEGER or CHAR');

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
      IF last_val_tk = TK_CHAR THEN
        ordv := LLVMBuildZExt(builder, ordv, i16ty, MakeCStr(''))
      ELSE IF last_val_tk <> TK_INTEGER THEN
        AbortWith('codegen: a set element must be INTEGER or CHAR');
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

FUNCTION CodegenBinOp(op: Str255; left_node, right_node: ADRMEM): ADRMEM;
VAR
  lval, rval, res: ADRMEM;
  ltk, rtk: INTEGER;
  gep_idx, ptr_elem_ty: ADRMEM;
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

  { A bare INTEGER literal operand adapts to the other side's wider/
    differently-signed integer type, mirroring the reference's
    literal_context threading (typecheck/exprs.py): CodegenExpr always
    builds an IntLiteral as plain 16-bit INTEGER with no knowledge of
    context, so rebuild it at the sibling operand's own width here instead
    of letting the ltk<>rtk check below reject it as "mixed-type". }
  IF (ltk = TK_INTEGER) AND IsIntLiteralLike(left_node) AND IsWideIntTk(rtk) THEN
  BEGIN
    lval := LLVMConstInt(LLVMTypeForTk(rtk), IntLiteralValue(left_node), 1);
    ltk := rtk;
  END
  ELSE IF (rtk = TK_INTEGER) AND IsIntLiteralLike(right_node) AND IsWideIntTk(ltk) THEN
  BEGIN
    rval := LLVMConstInt(LLVMTypeForTk(ltk), IntLiteralValue(right_node), 1);
    rtk := ltk;
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
  ELSE IF (ltk = TK_ADRMEM) AND (TypeKind(rtk) = TK_POINTER) THEN
    { NIL (an ADRMEM constant) against a typed pointer -- both are the
      same opaque i8* value, only the tracked tag differs, the same
      mutual compatibility TypesCompatibleForAssign already applies. }
    ltk := rtk
  ELSE IF (rtk = TK_ADRMEM) AND (TypeKind(ltk) = TK_POINTER) THEN
    rtk := ltk
  ELSE IF (op = 'SLASH') AND IsIntegerFamilyTk(ltk) AND IsIntegerFamilyTk(rtk) THEN
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
      way: `int_part * 10.0 + (...)` silently emitted no FAdd at all). }
    lval := LLVMBuildSIToFP(builder, lval, dblty, MakeCStr(''));
    rval := LLVMBuildSIToFP(builder, rval, dblty, MakeCStr(''));
    ltk := TK_REAL;
    rtk := TK_REAL;
  END
  ELSE IF IsIntegerFamilyTk(ltk) AND ((rtk = TK_REAL) OR (rtk = TK_REAL32)) THEN
  BEGIN
    { Mixed INTEGER-family/REAL operand: the integer side implicitly
      promotes to the other side's floating width, matching the
      reference's is_real widening (codegen_binop). Same chain-placement
      rationale as the SLASH branch above. }
    lval := LLVMBuildSIToFP(builder, lval, LLVMTypeForTk(rtk), MakeCStr(''));
    ltk := rtk;
  END
  ELSE IF ((ltk = TK_REAL) OR (ltk = TK_REAL32)) AND IsIntegerFamilyTk(rtk) THEN
  BEGIN
    rval := LLVMBuildSIToFP(builder, rval, LLVMTypeForTk(ltk), MakeCStr(''));
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
  IF (TypeKind(ltk) = TK_VECTOR) OR (TypeKind(rtk) = TK_VECTOR) THEN
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
    IF ltk = TK_CHAR THEN lval := LLVMBuildZExt(builder, lval, i16ty, MakeCStr(''))
    ELSE IF ltk <> TK_INTEGER THEN
      AbortWith('codegen: IN requires an INTEGER or CHAR left operand');
    IF TypeKind(rtk) <> TK_SET THEN
      AbortWith('codegen: IN requires a SET right operand');
    res := CodegenSetMember(lval, rval);
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF (TypeKind(ltk) = TK_SET) AND (TypeKind(rtk) = TK_SET) THEN
    res := CodegenSetBinOp(op, lval, rval)
  ELSE IF (op = 'PLUS') AND ((ltk = TK_ADRMEM) OR (TypeKind(ltk) = TK_POINTER)) AND IsIntegerFamilyTk(rtk) THEN
  BEGIN
    { ADRMEM and ^CHAR are byte-addressed, but a general POINTER must use
      its declared pointee type as LLVM's GEP source element type. In
      particular, ^ADRMEM is a pointer-slot array, not a byte array. }
    IF ltk = TK_ADRMEM THEN ptr_elem_ty := i8ty
    ELSE ptr_elem_ty := LLVMTypeForTk(types[ltk].elem_tid);
    gep_idx := AllocPtrArray(1);
    SetPtrArrayElem(gep_idx, 0, rval);
    res := LLVMBuildGEP2(builder, ptr_elem_ty, lval, gep_idx, 1, MakeCStr(''));
    last_val_tk := ltk;
  END
  ELSE IF (op = 'PLUS') AND ((rtk = TK_ADRMEM) OR (TypeKind(rtk) = TK_POINTER)) AND IsIntegerFamilyTk(ltk) THEN
  BEGIN
    IF rtk = TK_ADRMEM THEN ptr_elem_ty := i8ty
    ELSE ptr_elem_ty := LLVMTypeForTk(types[rtk].elem_tid);
    gep_idx := AllocPtrArray(1);
    SetPtrArrayElem(gep_idx, 0, lval);
    res := LLVMBuildGEP2(builder, ptr_elem_ty, rval, gep_idx, 1, MakeCStr(''));
    last_val_tk := rtk;
  END
  ELSE IF ltk <> rtk THEN
  BEGIN
    AbortWith('codegen: mixed-type operands are not supported (no implicit promotion)');
    res := NIL;
  END
  ELSE IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE') THEN
  BEGIN
    { WORD/INTEGER8 compare via the same *signed* icmp as plain INTEGER --
      matching the Python reference, whose same-width WORD comparisons are
      signed at the LLVM instruction level too (only WRITE formatting and
      cross-width extension choice are signedness-aware there; this file
      has no cross-width mixing at all, so that distinction never applies
      here). }
    IF (ltk = TK_INTEGER) OR (ltk = TK_WORD) OR (ltk = TK_INTEGER8) OR (ltk = TK_WORD8) OR
       (ltk = TK_INTEGER32) OR (ltk = TK_WORD32) OR (ltk = TK_INTEGER64) OR (ltk = TK_WORD64) OR
       (ltk = TK_CHAR) OR (ltk = TK_BOOLEAN) OR (TypeKind(ltk) = TK_ENUM) THEN
    BEGIN
      { CHAR/BOOLEAN are ordinal in Pascal, so full ordering (not just EQ/
        NEQ) is meaningful for them too, and LLVM's icmp works the same way
        on their i8/i1 representations as on the integer widths above. }
      IF op = 'EQ' THEN res := LLVMBuildICmp(builder, LLVMIntEQ, lval, rval, MakeCStr(''))
      ELSE IF op = 'NEQ' THEN res := LLVMBuildICmp(builder, LLVMIntNE, lval, rval, MakeCStr(''))
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
    { Same rationale as the comparison branch above: +/-/*/DIV/MOD on
      WORD/INTEGER8 (and their wider WORD8/32/64, INTEGER32/64 siblings)
      reuse plain INTEGER's signed instructions -- two's complement
      add/sub/mul don't care about signedness, and the reference hardcodes
      sdiv/srem even for the WORD family. }
    IF op = 'PLUS' THEN res := LLVMBuildAdd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MINUS' THEN res := LLVMBuildSub(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MUL' THEN res := LLVMBuildMul(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'DIV' THEN res := LLVMBuildSDiv(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MOD' THEN res := LLVMBuildSRem(builder, lval, rval, MakeCStr(''))
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
  CodegenBinOp := res;
END;

FUNCTION CodegenUnaryOp(op: Str255; operand_node: ADRMEM): ADRMEM;
VAR
  v, res: ADRMEM;
  tk: INTEGER;
BEGIN
  v := CodegenExpr(operand_node);
  tk := last_val_tk;
  IF TypeKind(tk) = TK_VECTOR THEN
  BEGIN
    res := CodegenVectorUnaryOp(op, v, tk);
    last_val_tk := tk;
    CodegenUnaryOp := res;
    RETURN;
  END;
  IF op = 'MINUS' THEN
  BEGIN
    IF (tk = TK_INTEGER) OR (tk = TK_WORD) THEN res := LLVMBuildSub(builder, LLVMConstInt(i16ty, 0, 1), v, MakeCStr(''))
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
    ret_class := FuncRetAggClass(ri);
    IF ret_class <> 0 THEN
      ClassifyAggregate(routines[ri].ret_tk, ret_class, ret_npieces, ret_pk, ret_pb);
    call_args := AllocPtrArray(nargs * 2 + 1);
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
    FOR i := 0 TO nargs - 1 DO
    BEGIN
      pieces_emitted := FALSE;
      arg_node := ArrItem(args_arr, i);
      IF i >= routines[ri].nparams THEN
      BEGIN
        { Variadic tail argument: there is no formal parameter at all, so
          none of the param_is_var/param_needs_copy machinery applies (those
          arrays only have nparams valid entries). Evaluate the argument and
          apply C's default argument promotions, exactly as the reference's
          codegen_c_abi_call does for the same tail. }
        v := CodegenExpr(arg_node);
        v := VariadicPromote(v, last_val_tk, name);
      END
      ELSE IF routines[ri].param_is_var[i + 1] THEN
      BEGIN
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
          END;
        END
        ELSE IF NodeType(arg_node) = 'Designator' THEN
        BEGIN
          v := ComputeDesignatorAddress(arg_node);
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
      END
      ELSE IF routines[ri].param_needs_copy[i + 1] THEN
      BEGIN
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
          END;
        END
        ELSE IF NodeType(arg_node) = 'Designator' THEN
        BEGIN
          v := ComputeDesignatorAddress(arg_node);
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
          LLVMBuildStore(builder, CodegenExpr(arg_node), v);
        END
        ELSE
        BEGIN
          { Any other value-mode aggregate-shaped expression: CodegenExpr
            produces it as an SSA value, so materialize it into a fresh temp
            to get an address to classify/copy from. }
          v_tmp := CodegenExpr(arg_node);
          v := EntryAlloca(LLVMTypeForTk(routines[ri].param_tk[i + 1]), '');
          LLVMBuildStore(builder, v_tmp, v);
        END;
        ClassifyAggregate(routines[ri].param_tk[i + 1], agg_class, n_pieces, piece_kind, piece_bytes);
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
      END
      ELSE
      BEGIN
        v := CodegenExpr(arg_node);
        { Value-mode call arguments get the same literal-adaptation leniency
          as an assignment RHS (e.g. a bare INTEGER literal passed to a CINT
          [C] EXTERN parameter, as with cJSON_CreateBool(1) or exit(1)):
          reuse CoerceForAssign rather than a bare tid-equality check. }
        v := CoerceForAssign(v, last_val_tk, routines[ri].param_tk[i + 1], arg_node, name);
      END;
      IF NOT pieces_emitted THEN
      BEGIN
        SetPtrArrayElem(call_args, llvm_ai, v);
        llvm_ai := llvm_ai + 1;
      END;
    END;
    res := LLVMBuildCall2(builder, routines[ri].fnty, routines[ri].fn, call_args, llvm_ai, MakeCStr(''));
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
        ClassifyAggregate(routines[ri].param_tk[i + 1], agg_class, n_pieces, piece_kind, piece_bytes);
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
BEGIN
  nm := GetStr(node, 'name');
  symi := LookupSym(nm);
  selectors := GetObj(node, 'selectors');
  nsel := ArrSize(selectors);
  IF (symi = 0) AND (nsel = 0) AND RoutineIsFunc(LookupRoutine(nm)) THEN
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
  END;

  FOR si := 0 TO nsel - 1 DO
  BEGIN
    sel := ArrItem(selectors, si);
    kind := GetStr(sel, 'kind');
    IF kind = 'INDEX' THEN
    BEGIN
      IF (TypeKind(cur_tid) <> TK_ARRAY) AND (TypeKind(cur_tid) <> TK_LSTRING)
        AND (TypeKind(cur_tid) <> TK_STRING) AND (TypeKind(cur_tid) <> TK_VECTOR) THEN
        AbortWith('codegen: an INDEX selector was applied to a non-array');
      idx_expr := GetObj(sel, 'index_or_field');
      { A vector lane index is 0-based (types[].lo = 0). A constant lane
        index outside 0..lanes-1 is a compile-time error -- the same
        re-validation M0 does for the type itself, since this file also
        lowers frozen ASTs the typechecker never saw. A variable index is
        not range-checked (no $INDEXCK machinery; arrays are unchecked
        too). }
      IF (TypeKind(cur_tid) = TK_VECTOR) AND FoldConstInt(idx_expr, folded) THEN
        IF (folded < 0) OR (folded > types[cur_tid].hi) THEN
          AbortWith('codegen: vector lane index out of range');
      idx_val := CodegenExpr(idx_expr);
      { The reference codegen (resolve_designator_ptr_typed, types_map.py)
        accepts any integer-family index width -- it just subtracts the
        lower bound using a constant of the index's own LLVM type and lets
        GEP take an index of whatever width it is, not just a plain
        16-bit INTEGER. Match that here instead of requiring TK_INTEGER. }
      IF (last_val_tk <> TK_INTEGER) AND (last_val_tk <> TK_WORD)
        AND (last_val_tk <> TK_INTEGER8) AND (last_val_tk <> TK_WORD8)
        AND (last_val_tk <> TK_INTEGER32) AND (last_val_tk <> TK_WORD32)
        AND (last_val_tk <> TK_INTEGER64) AND (last_val_tk <> TK_WORD64) THEN
        AbortWith('codegen: an array index must be an integer-family type');
      offset := LLVMBuildSub(builder, idx_val, LLVMConstInt(LLVMTypeForTk(last_val_tk), types[cur_tid].lo, 1), MakeCStr(''));
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
      cur_tid := types[cur_tid].elem_tid;
    END
    ELSE IF kind = 'DEREF' THEN
    BEGIN
      IF TypeKind(cur_tid) = TK_FILE THEN
      BEGIN
        { F^: the runtime-owned current-component buffer, mirroring the
          reference's _file_buffer_ptr. TEXT files get a lazy-touch hook
          first (touch=True only for ASCII structure, types[].hi = 1). }
        file_handle := LLVMBuildLoad2(builder, i8ptrty, base_ptr, MakeCStr(''));
        file_fcb := LLVMBuildBitCast(builder, file_handle, LLVMPointerType(filefcbty, 0), MakeCStr(''));
        file_call_args := AllocPtrArray(1);
        SetPtrArrayElem(file_call_args, 0, file_fcb);
        IF types[cur_tid].hi = 1 THEN
          discard := LLVMBuildCall2(builder, file_touch_buffer_fnty, file_touch_buffer_fn, file_call_args, 1, MakeCStr(''));
        file_raw_buf := LLVMBuildCall2(builder, file_buffer_fnty, file_buffer_fn, file_call_args, 1, MakeCStr(''));
        cur_tid := types[cur_tid].elem_tid;
        base_ptr := LLVMBuildBitCast(builder, file_raw_buf, LLVMPointerType(LLVMTypeForTk(cur_tid), 0), MakeCStr(''));
      END
      ELSE BEGIN
        IF TypeKind(cur_tid) <> TK_POINTER THEN
          AbortWith('codegen: a DEREF selector was applied to a non-pointer');
        base_ptr := LLVMBuildLoad2(builder, LLVMTypeForTk(cur_tid), base_ptr, MakeCStr(''));
        cur_tid := types[cur_tid].elem_tid;
      END;
    END
    ELSE IF kind = 'FIELD' THEN
    BEGIN
      IF TypeKind(cur_tid) = TK_LSTRING THEN
      BEGIN
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
        cur_tid := fields[fi].field_tid;
        base_ptr := LLVMBuildBitCast(builder, base_ptr, LLVMPointerType(LLVMTypeForTk(cur_tid), 0), MakeCStr(''));
      END;
    END
    ELSE
      AbortWith2('codegen: unhandled selector kind: ', kind);
  END;

  last_val_tk := cur_tid;
  ComputeDesignatorAddress := base_ptr;
END;

FUNCTION CodegenSimpleBuiltin(nm: Str255; args: ADRMEM): ADRMEM;
{ The math/ordinal builtins that need no libpascalrt support: pure inline
  LLVM IR (CHR/ORD/ODD/SUCC/PRED/ABS/SQR), or a single libm call
  (SQRT/SIN/COS/LN/EXP/ARCTAN), mirroring the Python reference's exprs.py
  1:1 except where this dialect's INTEGER is 16-bit rather than the
  reference's 32-bit: ORD's result and TRUNC/ROUND's result are produced as
  i16 here, not i32 -- consistent with every other native-INTEGER value in
  this file, and with the dialect's own known 16-bit-INTEGER-overflow
  behavior (not a bug -- see the codebase's own vintage-dialect notes). }
VAR
  v, v2, is_neg, neg, half, res, hi16, lo16: ADRMEM;
  argtk, argtk2: INTEGER;
BEGIN
  v := CodegenExpr(ArrItem(args, 0));
  argtk := last_val_tk;
  IF nm = 'CHR' THEN
  BEGIN
    res := LLVMBuildTrunc(builder, v, i8ty, MakeCStr(''));
    last_val_tk := TK_CHAR;
  END
  ELSE IF nm = 'ORD' THEN
  BEGIN
    IF argtk = TK_CHAR THEN
    BEGIN
      res := LLVMBuildZExt(builder, v, i16ty, MakeCStr(''));
      last_val_tk := TK_INTEGER;
    END
    ELSE IF TypeKind(argtk) = TK_ENUM THEN
    BEGIN
      { An enum ordinal is physically i32 (the enum's storage); tag the
        result INTEGER32 rather than INTEGER so WRITE's %d path doesn't
        try to sign-extend an already-32-bit value. }
      res := v;
      last_val_tk := TK_INTEGER32;
    END
    ELSE
    BEGIN
      res := v;
      last_val_tk := TK_INTEGER;
    END;
  END
  ELSE IF nm = 'ODD' THEN
  BEGIN
    res := LLVMBuildAnd(builder, v, LLVMConstInt(i16ty, 1, 0), MakeCStr(''));
    res := LLVMBuildICmp(builder, LLVMIntNE, res, LLVMConstInt(i16ty, 0, 0), MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF nm = 'SUCC' THEN
  BEGIN
    IF argtk = TK_CHAR THEN res := LLVMBuildAdd(builder, v, LLVMConstInt(i8ty, 1, 0), MakeCStr(''))
    ELSE IF TypeKind(argtk) = TK_ENUM THEN res := LLVMBuildAdd(builder, v, LLVMConstInt(i32ty, 1, 0), MakeCStr(''))
    ELSE res := LLVMBuildAdd(builder, v, LLVMConstInt(i16ty, 1, 0), MakeCStr(''));
    last_val_tk := argtk;
  END
  ELSE IF nm = 'PRED' THEN
  BEGIN
    IF argtk = TK_CHAR THEN res := LLVMBuildSub(builder, v, LLVMConstInt(i8ty, 1, 0), MakeCStr(''))
    ELSE IF TypeKind(argtk) = TK_ENUM THEN res := LLVMBuildSub(builder, v, LLVMConstInt(i32ty, 1, 0), MakeCStr(''))
    ELSE res := LLVMBuildSub(builder, v, LLVMConstInt(i16ty, 1, 0), MakeCStr(''));
    last_val_tk := argtk;
  END
  ELSE IF nm = 'ABS' THEN
  BEGIN
    IF argtk = TK_REAL THEN
    BEGIN
      is_neg := LLVMBuildFCmp(builder, LLVMRealOLT, v, LLVMConstReal(dblty, 0.0), MakeCStr(''));
      neg := LLVMBuildFSub(builder, LLVMConstReal(dblty, 0.0), v, MakeCStr(''));
    END
    ELSE
    BEGIN
      is_neg := LLVMBuildICmp(builder, LLVMIntSLT, v, LLVMConstInt(i16ty, 0, 1), MakeCStr(''));
      neg := LLVMBuildSub(builder, LLVMConstInt(i16ty, 0, 1), v, MakeCStr(''));
    END;
    res := LLVMBuildSelect(builder, is_neg, neg, v, MakeCStr(''));
    last_val_tk := argtk;
  END
  ELSE IF nm = 'SQR' THEN
  BEGIN
    IF argtk = TK_REAL THEN res := LLVMBuildFMul(builder, v, v, MakeCStr(''))
    ELSE res := LLVMBuildMul(builder, v, v, MakeCStr(''));
    last_val_tk := argtk;
  END
  ELSE IF (nm = 'SQRT') OR (nm = 'SIN') OR (nm = 'COS') OR (nm = 'LN') OR (nm = 'EXP') OR (nm = 'ARCTAN') THEN
  BEGIN
    IF argtk <> TK_REAL THEN v := LLVMBuildSIToFP(builder, v, dblty, MakeCStr(''));
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
    IF argtk <> TK_REAL THEN v := LLVMBuildSIToFP(builder, v, dblty, MakeCStr(''));
    res := LLVMBuildFPToSI(builder, v, i16ty, MakeCStr(''));
    last_val_tk := TK_INTEGER;
  END
  ELSE IF nm = 'ROUND' THEN
  BEGIN
    IF argtk <> TK_REAL THEN v := LLVMBuildSIToFP(builder, v, dblty, MakeCStr(''));
    is_neg := LLVMBuildFCmp(builder, LLVMRealOLT, v, LLVMConstReal(dblty, 0.0), MakeCStr(''));
    half := LLVMBuildSelect(builder, is_neg, LLVMConstReal(dblty, -0.5), LLVMConstReal(dblty, 0.5), MakeCStr(''));
    v := LLVMBuildFAdd(builder, v, half, MakeCStr(''));
    res := LLVMBuildFPToSI(builder, v, i16ty, MakeCStr(''));
    last_val_tk := TK_INTEGER;
  END
  ELSE IF nm = 'FLOAT' THEN
  BEGIN
    IF argtk = TK_REAL THEN res := v
    ELSE res := LLVMBuildSIToFP(builder, v, dblty, MakeCStr(''));
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

FUNCTION CodegenExpr(node: ADRMEM): ADRMEM;
VAR
  nt: Str255;
  nm: Str255;
  nmu: Str255;
  symi: INTEGER32;
  consti: INTEGER32;
  routi: INTEGER32;
  ch: Str255;
  res, addr, super_ptr, super_header: ADRMEM;
  result_tid: INTEGER;
  target_item, target_str, sizeof_synth: ADRMEM;
  sizeof_bytes: INTEGER32;
  call_args: ADRMEM;
  vsel_mask, vsel_a, vsel_b: ADRMEM;
  vsel_mask_tid, vsel_a_tid, vsel_b_tid: INTEGER;
BEGIN
  EnterExprLevel;
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN
  BEGIN
    res := LLVMConstInt(i16ty, GetInt(node, 'value'), 1);
    last_val_tk := TK_INTEGER;
  END
  ELSE IF nt = 'RealLiteral' THEN
  BEGIN
    res := LLVMConstReal(dblty, GetReal(node, 'value'));
    last_val_tk := TK_REAL;
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
    res := LLVMBuildBitCast(builder, symbols[symi].llvm_val, i8ptrty, MakeCStr(''));
    last_val_tk := TK_ADRMEM;
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
      res := LLVMBuildLoad2(builder, LLVMTypeForTk(symbols[symi].tk), symbols[symi].llvm_val, MakeCStr(''));
      last_val_tk := symbols[symi].tk;
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
  ELSE IF nt = 'Designator' THEN  BEGIN
    addr := ComputeDesignatorAddress(node);
    result_tid := last_val_tk;
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
    res := CodegenBinOp(GetStr(node, 'op'), GetObj(node, 'left'), GetObj(node, 'right'))
  ELSE IF nt = 'SetConstructor' THEN
    res := CodegenSetConstructor(node)
  ELSE IF nt = 'UnaryOp' THEN
    res := CodegenUnaryOp(GetStr(node, 'op'), GetObj(node, 'operand'))
  ELSE IF (nt = 'UpperExpr') OR (nt = 'LowerExpr') THEN
  BEGIN
    { LOWER/UPPER bound resolution, scoped to the fixed-bound cases this
      file's type system can represent: TYPE-declared ARRAY (static
      lo/hi), STRING(n) (lower=1, upper=n), LSTRING(n) (lower=0,
      upper=n -- the declared capacity, not the runtime length: the Python
      reference resolves the same static bound for these, see exprs.py's
      NamedType/ResolvedStringType/ResolvedLStringType branches). The
      dereferenced form UPPER(p^)/LOWER(p^) -- bounds of a pointee, with a
      dynamic upper bound for heap "super arrays" read from NEW's bound
      header -- is not supported: this file has neither super arrays nor
      multi-dimension arrays yet. }
    nm := GetStr(node, 'name');
    IF GetBool(node, 'deref') THEN
    BEGIN
      symi := LookupSym(nm);
      IF (symi = 0) OR (TypeKind(symbols[symi].tk) <> TK_POINTER) OR
         (NOT types[types[symbols[symi].tk].elem_tid].is_super) THEN
        AbortWith('codegen: UPPER/LOWER dereference requires a SUPER ARRAY pointer');
      IF nt = 'LowerExpr' THEN
        res := LLVMConstInt(i16ty, types[types[symbols[symi].tk].elem_tid].lo, 1)
      ELSE
      BEGIN
        super_ptr := LLVMBuildLoad2(builder, LLVMTypeForTk(symbols[symi].tk), symbols[symi].llvm_val, MakeCStr(''));
        super_ptr := LLVMBuildBitCast(builder, super_ptr, i8ptrty, MakeCStr(''));
        super_header := LLVMBuildGEP2(builder, i8ty, super_ptr,
          MakeArgs1(LLVMConstInt(i64ty, -8, 1)), 1, MakeCStr(''));
        super_header := LLVMBuildBitCast(builder, super_header, LLVMPointerType(i64ty, 0), MakeCStr(''));
        res := LLVMBuildLoad2(builder, i64ty, super_header, MakeCStr(''));
      END;
      last_val_tk := TK_INTEGER64;
    END
    ELSE
    BEGIN
    symi := LookupSym(nm);
    IF symi = 0 THEN
    BEGIN
      AbortWith2('codegen: undefined variable: ', nm);
      res := NIL;
    END
    ELSE
    BEGIN
      result_tid := symbols[symi].tk;
      IF TypeKind(result_tid) = TK_ARRAY THEN
      BEGIN
        IF nt = 'UpperExpr' THEN res := LLVMConstInt(i16ty, types[result_tid].hi, 1)
        ELSE res := LLVMConstInt(i16ty, types[result_tid].lo, 1);
      END
      ELSE IF TypeKind(result_tid) = TK_STRING THEN
      BEGIN
        IF nt = 'UpperExpr' THEN res := LLVMConstInt(i16ty, types[result_tid].hi, 1)
        ELSE res := LLVMConstInt(i16ty, 1, 1);
      END
      ELSE IF TypeKind(result_tid) = TK_LSTRING THEN
      BEGIN
        IF nt = 'UpperExpr' THEN res := LLVMConstInt(i16ty, types[result_tid].hi, 1)
        ELSE res := LLVMConstInt(i16ty, 0, 1);
      END
      ELSE IF TypeKind(result_tid) = TK_VECTOR THEN
      BEGIN
        { lo/hi were registered as 0/lanes-1, so the table read is identical
          to the TK_ARRAY case. }
        IF nt = 'UpperExpr' THEN res := LLVMConstInt(i16ty, types[result_tid].hi, 1)
        ELSE res := LLVMConstInt(i16ty, types[result_tid].lo, 1);
      END
      ELSE
      BEGIN
        AbortWith2('codegen: UPPER/LOWER not supported for variable: ', nm);
        res := NIL;
      END;
      last_val_tk := TK_INTEGER;
    END;
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
    nm := GetStr(node, 'name');
    IF nm = 'POSITN' THEN
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
    ELSE IF nm = 'DECODE' THEN
    BEGIN
      res := CodegenDecode(GetObj(node, 'args'));
      last_val_tk := TK_BOOLEAN;
    END
    ELSE IF (nm = 'CHR') OR (nm = 'ORD') OR (nm = 'ODD') OR (nm = 'SUCC') OR (nm = 'PRED')
      OR (nm = 'ABS') OR (nm = 'SQR') OR (nm = 'SQRT') OR (nm = 'SIN') OR (nm = 'COS')
      OR (nm = 'LN') OR (nm = 'EXP') OR (nm = 'ARCTAN') OR (nm = 'TRUNC') OR (nm = 'ROUND')
      OR (nm = 'FLOAT') OR (nm = 'HIBYTE') OR (nm = 'LOBYTE') OR (nm = 'WRD') OR (nm = 'WRD8') OR (nm = 'BYWORD') THEN
      res := CodegenSimpleBuiltin(nm, GetObj(node, 'args'))
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
      symi := LookupRoutine(nm);
      IF symi = 0 THEN
      BEGIN
        AbortWith2('codegen: undefined function: ', nm);
        res := NIL;
      END
      ELSE IF NOT routines[symi].is_func THEN
      BEGIN
        AbortWith2('codegen: called as a function but is a PROCEDURE: ', nm);
        res := NIL;
      END
      ELSE
        res := CodegenCallCommon(nm, GetObj(node, 'args'));
    END;
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unhandled expression kind: ', nt);
    res := NIL;
  END;
  LeaveExprLevel;
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
{ SCANEQ(L, P, S, I) / SCANNE(L, P, S, I): INTEGER -- scans up to L
  characters of S starting at 1-based position I, stopping at the first
  character equal to (SCANEQ) or not equal to (SCANNE) P; returns the
  1-based position of the stopping character, entirely libpascalrt's
  runtime `scaneq`/`scanne` (scaneq.c). }
VAR
  l_val, p_val, s_chars, s_len, i_val: ADRMEM;
  call_args, res32: ADRMEM;
BEGIN
  IF ArrSize(args) <> 4 THEN
    AbortWith('codegen: SCANEQ/SCANNE expects exactly 4 arguments');
  l_val := CodegenExpr(ArrItem(args, 0));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: SCANEQ/SCANNE''s L argument must be INTEGER');
  l_val := LLVMBuildSExt(builder, l_val, i32ty, MakeCStr(''));
  p_val := CodegenExpr(ArrItem(args, 1));
  IF last_val_tk <> TK_CHAR THEN
    AbortWith('codegen: SCANEQ/SCANNE''s P argument must be CHAR');
  ResolveStringExprCharsLen(ArrItem(args, 2), s_chars, s_len);
  i_val := CodegenExpr(ArrItem(args, 3));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: SCANEQ/SCANNE''s I argument must be INTEGER');
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
