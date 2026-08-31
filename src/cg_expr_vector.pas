{ Implementations for cg_expr_vector -- see cg_expr_vector.inc. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_expr_vector.inc'*)
IMPLEMENTATION OF cg_expr_vector;

FUNCTION CodegenVSplat(scalar_val: ADRMEM; scalar_tk: INTEGER; vec_tid: INTEGER; arg_node: ADRMEM): ADRMEM;
{ insertelement undef, x, 0  then a zero-mask shufflevector -> every lane
  becomes x. The zero mask is LLVMConstNull of <n x i32> (a zeroinitializer
  vector), which is exactly "take element 0 of the first operand for every
  result lane". }
VAR
  elem_tid: INTEGER;
  n: INTEGER32;  { types[].hi/.lo are INTEGER32 -- the reference rejects a
                   narrowing assign into a plain INTEGER slot }
  ev, undef_vec, ins, zeromask: ADRMEM;
BEGIN
  elem_tid := types[vec_tid].elem_tid;
  { Coerce the scalar to the element type (int widening, REAL32/REAL, ...) --
    reuses the assignment coercion path and its diagnostics. }
  ev := CoerceForAssign(scalar_val, scalar_tk, elem_tid, arg_node, 'VSPLAT');
  { BOOLEAN lanes are <n x i8> in memory (M0), not <n x i1>; widen the
    register i1 to match before it goes into the vector. }
  IF elem_tid = TK_BOOLEAN THEN
    ev := LLVMBuildZExt(builder, ev, i8ty, MakeCStr(''));
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  undef_vec := LLVMGetUndef(LLVMTypeForTk(vec_tid));
  ins := LLVMBuildInsertElement(builder, undef_vec, ev,
                                LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
  zeromask := LLVMConstNull(LLVMVectorType(i32ty, n));
  CodegenVSplat := LLVMBuildShuffleVector(builder, ins, undef_vec, zeromask, MakeCStr(''));
END;

FUNCTION CodegenVectorBinOp(op: Str255; lval, rval: ADRMEM; lvec_tid, rvec_tid: INTEGER): ADRMEM;
{ Both operands must be the SAME vector type -- there is no scalar-to-vector
  promotion (write VSPLAT). The instruction is chosen from the element kind:
  float lanes -> f* ; integer lanes -> the signed forms, with the unsigned
  divide/remainder for a WORD* element; boolean lanes -> bitwise (the mask is
  <n x i8> of 0/1, so and/or/xor act lanewise). }
VAR
  elem: INTEGER;
  res: ADRMEM;
BEGIN
  IF lvec_tid <> rvec_tid THEN
  BEGIN
    AbortWith('codegen: mixed-type operands are not supported (no implicit promotion)');
    CodegenVectorBinOp := NIL;
    RETURN;
  END;
  elem := types[lvec_tid].elem_tid;
  res := NIL;
  IF (elem = TK_REAL) OR (elem = TK_REAL32) THEN
  BEGIN
    IF op = 'PLUS' THEN res := LLVMBuildFAdd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MINUS' THEN res := LLVMBuildFSub(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MUL' THEN res := LLVMBuildFMul(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'SLASH' THEN res := LLVMBuildFDiv(builder, lval, rval, MakeCStr(''))
    ELSE AbortWith2('codegen: operator not defined for a float VECTOR: ', op);
  END
  ELSE IF elem = TK_BOOLEAN THEN
  BEGIN
    IF op = 'AND' THEN res := LLVMBuildAnd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'OR' THEN res := LLVMBuildOr(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'XOR' THEN res := LLVMBuildXor(builder, lval, rval, MakeCStr(''))
    ELSE AbortWith2('codegen: operator not defined for a BOOLEAN VECTOR: ', op);
  END
  ELSE IF IsIntegerFamilyTk(elem) THEN
  BEGIN
    IF op = 'PLUS' THEN res := LLVMBuildAdd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MINUS' THEN res := LLVMBuildSub(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'MUL' THEN res := LLVMBuildMul(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'AND' THEN res := LLVMBuildAnd(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'OR' THEN res := LLVMBuildOr(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'XOR' THEN res := LLVMBuildXor(builder, lval, rval, MakeCStr(''))
    ELSE IF op = 'DIV' THEN
    BEGIN
      IF IsUnsignedWordTk(elem) THEN res := LLVMBuildUDiv(builder, lval, rval, MakeCStr(''))
      ELSE res := LLVMBuildSDiv(builder, lval, rval, MakeCStr(''));
    END
    ELSE IF op = 'MOD' THEN
    BEGIN
      IF IsUnsignedWordTk(elem) THEN res := LLVMBuildURem(builder, lval, rval, MakeCStr(''))
      ELSE res := LLVMBuildSRem(builder, lval, rval, MakeCStr(''));
    END
    ELSE AbortWith2('codegen: operator not defined for an integer VECTOR: ', op);
  END
  ELSE
    AbortWith('codegen: VECTOR arithmetic requires an integer, float or BOOLEAN element type');
  CodegenVectorBinOp := res;
END;

FUNCTION CodegenVectorUnaryOp(op: Str255; v: ADRMEM; vec_tid: INTEGER): ADRMEM;
VAR
  elem: INTEGER;
  i: INTEGER32;
  n: INTEGER32;
  ones: ADRMEM;
  res: ADRMEM;
BEGIN
  elem := types[vec_tid].elem_tid;
  res := NIL;
  IF op = 'MINUS' THEN
  BEGIN
    IF (elem = TK_REAL) OR (elem = TK_REAL32) THEN
      res := LLVMBuildFNeg(builder, v, MakeCStr(''))
    ELSE IF IsIntegerFamilyTk(elem) THEN
      res := LLVMBuildSub(builder, LLVMConstNull(LLVMTypeForTk(vec_tid)), v, MakeCStr(''))
    ELSE
      AbortWith('codegen: unary MINUS requires an integer or float VECTOR');
  END
  ELSE IF op = 'NOT' THEN
  BEGIN
    IF elem = TK_BOOLEAN THEN
    BEGIN
      { A BOOLEAN lane is an i8 holding 0 or 1 (M0), so a full bitwise
        complement would produce 0xFF/0xFE and break the invariant; xor
        each lane with 1 instead. }
      n := types[vec_tid].hi - types[vec_tid].lo + 1;
      ones := AllocPtrArray(n);
      FOR i := 0 TO n - 1 DO
        SetPtrArrayElem(ones, i, LLVMConstInt(i8ty, 1, 0));
      res := LLVMBuildXor(builder, v, LLVMConstVector(ones, n), MakeCStr(''));
    END
    ELSE IF IsIntegerFamilyTk(elem) THEN
      res := LLVMBuildNot(builder, v, MakeCStr(''))
    ELSE
      AbortWith('codegen: NOT requires an integer or BOOLEAN VECTOR');
  END
  ELSE
    AbortWith2('codegen: unhandled unary VECTOR operator: ', op);
  CodegenVectorUnaryOp := res;
END;

FUNCTION UIntStr(n: INTEGER32): Str255;
{ Decimal text of a small non-negative integer -- no int->string helper
  exists in a unit this low, and the lane count (2..64) goes into the
  mangled intrinsic name. Digit-array reverse, mirroring cg_stmt's
  IntToStr255 (CHR needs a plain INTEGER, hence RETYPE). }
VAR
  v, digit: INTEGER32;
  tmp, res: Str255;
  len, i, out_i: INTEGER;
BEGIN
  v := n;
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
  FOR i := len DOWNTO 1 DO
  BEGIN
    out_i := out_i + 1;
    res[out_i] := tmp[i];
  END;
  res[0] := CHR(out_i);
  UIntStr := res;
END;

FUNCTION VecElemLLVMTag(elem: INTEGER): Str255;
{ The `<width><kind>` token LLVM uses in an overloaded intrinsic's vector
  suffix -- `i32`, `f64`, etc. BOOLEAN lanes are <n x i8> (M0). }
BEGIN
  IF (elem = TK_INTEGER8) OR (elem = TK_WORD8) OR (elem = TK_CHAR) OR (elem = TK_BOOLEAN) THEN
    VecElemLLVMTag := 'i8'
  ELSE IF (elem = TK_INTEGER) OR (elem = TK_WORD) THEN
    VecElemLLVMTag := 'i16'
  ELSE IF (elem = TK_INTEGER32) OR (elem = TK_WORD32) THEN
    VecElemLLVMTag := 'i32'
  ELSE IF (elem = TK_INTEGER64) OR (elem = TK_WORD64) THEN
    VecElemLLVMTag := 'i64'
  ELSE IF elem = TK_REAL32 THEN
    VecElemLLVMTag := 'f32'
  ELSE IF elem = TK_REAL THEN
    VecElemLLVMTag := 'f64'
  ELSE
  BEGIN
    AbortWith('codegen: no LLVM vector tag for this element kind');
    VecElemLLVMTag := 'i8';
  END;
END;

FUNCTION CodegenVReduce(nm: Str255; vec_val: ADRMEM; vec_tid: INTEGER): ADRMEM;
VAR
  elem: INTEGER;
  n: INTEGER32;
  is_float, is_uns, needs_start, is_mask_reduce: BOOLEAN;
  base, mangled: Str255;
  scalar_ty, vecty, start_val, fnty, fn, callres: ADRMEM;
  params, args: ADRMEM;
BEGIN
  elem := types[vec_tid].elem_tid;
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  is_float := (elem = TK_REAL) OR (elem = TK_REAL32);
  is_uns := IsUnsignedWordTk(elem);
  is_mask_reduce := (nm = 'VANY') OR (nm = 'VALL');
  needs_start := FALSE;

  IF is_mask_reduce THEN
  BEGIN
    IF elem <> TK_BOOLEAN THEN
      AbortWith2('codegen: reduction requires a VECTOR OF BOOLEAN: ', nm);
    IF nm = 'VANY' THEN base := 'or' ELSE base := 'and';
  END
  ELSE IF (nm = 'VSUM') OR (nm = 'VPROD') THEN
  BEGIN
    IF NOT (is_float OR IsIntegerFamilyTk(elem)) THEN
      AbortWith2('codegen: reduction requires a numeric VECTOR: ', nm);
    IF is_float THEN
    BEGIN
      needs_start := TRUE;
      IF nm = 'VSUM' THEN base := 'fadd' ELSE base := 'fmul';
    END
    ELSE
      IF nm = 'VSUM' THEN base := 'add' ELSE base := 'mul';
  END
  ELSE IF (nm = 'VMIN') OR (nm = 'VMAX') THEN
  BEGIN
    IF NOT (is_float OR IsIntegerFamilyTk(elem) OR (elem = TK_CHAR)) THEN
      AbortWith2('codegen: reduction requires a numeric or CHAR VECTOR: ', nm);
    IF is_float THEN
    BEGIN
      IF nm = 'VMIN' THEN base := 'fmin' ELSE base := 'fmax';
    END
    ELSE IF is_uns THEN
    BEGIN
      IF nm = 'VMIN' THEN base := 'umin' ELSE base := 'umax';
    END
    ELSE
      IF nm = 'VMIN' THEN base := 'smin' ELSE base := 'smax';
  END
  ELSE
    AbortWith2('codegen: unknown reduction builtin: ', nm);

  { <n x elem> and the scalar result type. }
  IF elem = TK_BOOLEAN THEN scalar_ty := i8ty
  ELSE scalar_ty := LLVMTypeForTk(elem);
  vecty := LLVMTypeForTk(vec_tid);

  mangled := 'llvm.vector.reduce.';
  CONCAT(mangled, base);
  CONCAT(mangled, '.v');
  CONCAT(mangled, UIntStr(n));
  CONCAT(mangled, VecElemLLVMTag(elem));

  IF needs_start THEN
  BEGIN
    params := AllocPtrArray(2);
    SetPtrArrayElem(params, 0, scalar_ty);
    SetPtrArrayElem(params, 1, vecty);
    fnty := LLVMFunctionType(scalar_ty, params, 2, 0);
    { An ordered reduction: 0.0 start for fadd, 1.0 for fmul, and no
      `reassoc` flag on the call -- results are deterministic. }
    IF base = 'fadd' THEN start_val := LLVMConstReal(scalar_ty, 0.0)
    ELSE start_val := LLVMConstReal(scalar_ty, 1.0);
    args := AllocPtrArray(2);
    SetPtrArrayElem(args, 0, start_val);
    SetPtrArrayElem(args, 1, vec_val);
  END
  ELSE
  BEGIN
    params := AllocPtrArray(1);
    SetPtrArrayElem(params, 0, vecty);
    fnty := LLVMFunctionType(scalar_ty, params, 1, 0);
    args := AllocPtrArray(1);
    SetPtrArrayElem(args, 0, vec_val);
  END;

  fn := LLVMGetNamedFunction(modl, MakeCStr(mangled));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr(mangled), fnty);

  IF needs_start THEN
    callres := LLVMBuildCall2(builder, fnty, fn, args, 2, MakeCStr(''))
  ELSE
    callres := LLVMBuildCall2(builder, fnty, fn, args, 1, MakeCStr(''));

  IF is_mask_reduce THEN
  BEGIN
    { or/and over <n x i8> 0/1 lanes -> i8 0/1; narrow to the i1 a scalar
      BOOLEAN register is. }
    callres := LLVMBuildTrunc(builder, callres, i1ty, MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE
    last_val_tk := elem;

  CodegenVReduce := callres;
END;

FUNCTION CodegenVectorCmp(op: Str255; lval, rval: ADRMEM; lvec_tid, rvec_tid: INTEGER): ADRMEM;
{ icmp/fcmp lanewise -> <n x i1>, then zext to the <n x i8> a BOOLEAN
  vector is stored as. Integer predicates are signed except for a WORD*
  element; CHAR/BOOLEAN elements use signed too, matching scalar
  CodegenBinOp (their values are small and non-negative). }
VAR
  elem: INTEGER;
  n: INTEGER32;
  is_float, uns: BOOLEAN;
  cmp: ADRMEM;
BEGIN
  IF lvec_tid <> rvec_tid THEN
  BEGIN
    AbortWith('codegen: mixed-type operands are not supported (no implicit promotion)');
    CodegenVectorCmp := NIL;
    RETURN;
  END;
  elem := types[lvec_tid].elem_tid;
  n := types[lvec_tid].hi - types[lvec_tid].lo + 1;
  is_float := (elem = TK_REAL) OR (elem = TK_REAL32);
  uns := IsUnsignedWordTk(elem);
  cmp := NIL;
  IF is_float THEN
  BEGIN
    IF op = 'EQ' THEN cmp := LLVMBuildFCmp(builder, LLVMRealOEQ, lval, rval, MakeCStr(''))
    ELSE IF op = 'NEQ' THEN cmp := LLVMBuildFCmp(builder, LLVMRealONE, lval, rval, MakeCStr(''))
    ELSE IF op = 'LT' THEN cmp := LLVMBuildFCmp(builder, LLVMRealOLT, lval, rval, MakeCStr(''))
    ELSE IF op = 'LE' THEN cmp := LLVMBuildFCmp(builder, LLVMRealOLE, lval, rval, MakeCStr(''))
    ELSE IF op = 'GT' THEN cmp := LLVMBuildFCmp(builder, LLVMRealOGT, lval, rval, MakeCStr(''))
    ELSE IF op = 'GE' THEN cmp := LLVMBuildFCmp(builder, LLVMRealOGE, lval, rval, MakeCStr(''))
    ELSE AbortWith2('codegen: bad VECTOR comparison operator: ', op);
  END
  ELSE
  BEGIN
    IF op = 'EQ' THEN cmp := LLVMBuildICmp(builder, LLVMIntEQ, lval, rval, MakeCStr(''))
    ELSE IF op = 'NEQ' THEN cmp := LLVMBuildICmp(builder, LLVMIntNE, lval, rval, MakeCStr(''))
    ELSE IF op = 'LT' THEN
    BEGIN
      IF uns THEN cmp := LLVMBuildICmp(builder, LLVMIntULT, lval, rval, MakeCStr(''))
      ELSE cmp := LLVMBuildICmp(builder, LLVMIntSLT, lval, rval, MakeCStr(''));
    END
    ELSE IF op = 'LE' THEN
    BEGIN
      IF uns THEN cmp := LLVMBuildICmp(builder, LLVMIntULE, lval, rval, MakeCStr(''))
      ELSE cmp := LLVMBuildICmp(builder, LLVMIntSLE, lval, rval, MakeCStr(''));
    END
    ELSE IF op = 'GT' THEN
    BEGIN
      IF uns THEN cmp := LLVMBuildICmp(builder, LLVMIntUGT, lval, rval, MakeCStr(''))
      ELSE cmp := LLVMBuildICmp(builder, LLVMIntSGT, lval, rval, MakeCStr(''));
    END
    ELSE IF op = 'GE' THEN
    BEGIN
      IF uns THEN cmp := LLVMBuildICmp(builder, LLVMIntUGE, lval, rval, MakeCStr(''))
      ELSE cmp := LLVMBuildICmp(builder, LLVMIntSGE, lval, rval, MakeCStr(''));
    END
    ELSE AbortWith2('codegen: bad VECTOR comparison operator: ', op);
  END;
  CodegenVectorCmp := LLVMBuildZExt(builder, cmp, LLVMVectorType(i8ty, n), MakeCStr(''));
END;

FUNCTION CodegenVSelect(mask_val, a_val, b_val: ADRMEM;
                        mask_tid, a_tid, b_tid: INTEGER): ADRMEM;
{ trunc the <n x i8> mask to <n x i1>, then a lanewise select. }
VAR
  n: INTEGER32;
  cond: ADRMEM;
BEGIN
  IF (TypeKind(mask_tid) <> TK_VECTOR) OR (types[mask_tid].elem_tid <> TK_BOOLEAN) THEN
    AbortWith('codegen: VSELECT mask must be a VECTOR OF BOOLEAN');
  IF a_tid <> b_tid THEN
    AbortWith('codegen: VSELECT branches must have the same VECTOR type');
  IF TypeKind(a_tid) <> TK_VECTOR THEN
    AbortWith('codegen: VSELECT branches must be VECTOR values');
  IF (types[mask_tid].hi - types[mask_tid].lo) <> (types[a_tid].hi - types[a_tid].lo) THEN
    AbortWith('codegen: VSELECT mask and branch lane counts differ');
  n := types[a_tid].hi - types[a_tid].lo + 1;
  cond := LLVMBuildTrunc(builder, mask_val, LLVMVectorType(i1ty, n), MakeCStr(''));
  CodegenVSelect := LLVMBuildSelect(builder, cond, a_val, b_val, MakeCStr(''));
END;

FUNCTION VecIdxTkOK(idx_tk: INTEGER): BOOLEAN;
BEGIN
  VecIdxTkOK := (idx_tk = TK_INTEGER) OR (idx_tk = TK_WORD)
    OR (idx_tk = TK_INTEGER8) OR (idx_tk = TK_WORD8)
    OR (idx_tk = TK_INTEGER32) OR (idx_tk = TK_WORD32)
    OR (idx_tk = TK_INTEGER64) OR (idx_tk = TK_WORD64);
END;

FUNCTION CodegenVectorEltPtr(arr_ptr: ADRMEM; arr_tid: INTEGER;
                             idx_val: ADRMEM; idx_tk: INTEGER;
                             vec_tid: INTEGER; idx_node: ADRMEM): ADRMEM;
VAR
  n: INTEGER32;
  folded: INTEGER64;
  offset, gep_idx: ADRMEM;
BEGIN
  IF TypeKind(arr_tid) <> TK_ARRAY THEN
    AbortWith('codegen: VLOAD/VSTORE first argument must be an ARRAY variable');
  IF types[vec_tid].elem_tid = TK_BOOLEAN THEN
    AbortWith('codegen: VLOAD/VSTORE does not support BOOLEAN vectors (a mask is not a memory format)');
  IF types[arr_tid].elem_tid <> types[vec_tid].elem_tid THEN
    AbortWith('codegen: VLOAD/VSTORE array element type must match the vector element type exactly');
  IF NOT VecIdxTkOK(idx_tk) THEN
    AbortWith('codegen: VLOAD/VSTORE index must be an integer-family type');
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  { Compile-time bounds check for a constant index only -- there is no
    $INDEXCK machinery, plain array subscripts are unchecked too. }
  IF FoldConstInt(idx_node, folded) THEN
    IF (folded < types[arr_tid].lo) OR (folded + n - 1 > types[arr_tid].hi) THEN
      AbortWith('codegen: VLOAD/VSTORE runs past the end of the array');
  offset := LLVMBuildSub(builder, idx_val,
                         LLVMConstInt(LLVMTypeForTk(idx_tk), types[arr_tid].lo, 1),
                         MakeCStr(''));
  IF types[arr_tid].is_super THEN
  BEGIN
    gep_idx := AllocPtrArray(1);
    SetPtrArrayElem(gep_idx, 0, offset);
    CodegenVectorEltPtr := LLVMBuildGEP2(builder, LLVMTypeForTk(arr_tid), arr_ptr, gep_idx, 1, MakeCStr(''));
  END
  ELSE
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, offset);
    CodegenVectorEltPtr := LLVMBuildGEP2(builder, LLVMTypeForTk(arr_tid), arr_ptr, gep_idx, 2, MakeCStr(''));
  END;
END;

FUNCTION CodegenVLoad(arr_ptr: ADRMEM; arr_tid: INTEGER;
                      idx_val: ADRMEM; idx_tk: INTEGER;
                      vec_tid: INTEGER; idx_node: ADRMEM): ADRMEM;
VAR
  eltp, ld: ADRMEM;
BEGIN
  eltp := CodegenVectorEltPtr(arr_ptr, arr_tid, idx_val, idx_tk, vec_tid, idx_node);
  ld := LLVMBuildLoad2(builder, LLVMTypeForTk(vec_tid), eltp, MakeCStr(''));
  { Element (not vector) alignment: the array is only element-aligned and i
    is arbitrary, so a wider claim would be a lie. }
  LLVMSetAlignment(ld, TypeAlignBytes(types[vec_tid].elem_tid));
  CodegenVLoad := ld;
END;

PROCEDURE CodegenVStore(arr_ptr: ADRMEM; arr_tid: INTEGER;
                        idx_val: ADRMEM; idx_tk: INTEGER;
                        vec_val: ADRMEM; vec_tid: INTEGER; idx_node: ADRMEM);
{ Per-lane extract + scalar store. A single `store <n x T>` would default
  to the vector's ABI alignment, an over-claim for an element-aligned
  array, and the [C] binding for LLVMBuildStore discards the instruction
  ref so its alignment can't be lowered. N element-aligned scalar stores
  are correct for any index; the backend re-fuses them where it's legal. }
VAR
  elem_tid: INTEGER;
  n, k: INTEGER32;
  base_eltp, elemty, lane, lanep, kidx: ADRMEM;
BEGIN
  elem_tid := types[vec_tid].elem_tid;
  n := types[vec_tid].hi - types[vec_tid].lo + 1;
  base_eltp := CodegenVectorEltPtr(arr_ptr, arr_tid, idx_val, idx_tk, vec_tid, idx_node);
  elemty := LLVMTypeForTk(elem_tid);
  FOR k := 0 TO n - 1 DO
  BEGIN
    kidx := AllocPtrArray(1);
    SetPtrArrayElem(kidx, 0, LLVMConstInt(i32ty, k, 0));
    lanep := LLVMBuildGEP2(builder, elemty, base_eltp, kidx, 1, MakeCStr(''));
    lane := LLVMBuildExtractElement(builder, vec_val, LLVMConstInt(i32ty, k, 0), MakeCStr(''));
    LLVMBuildStore(builder, lane, lanep);
  END;
END;

BEGIN
END.
