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

BEGIN
END.
