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

BEGIN
END.
