{ Implementations for cg_expr_sets. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
(*$INCLUDE:'cg_expr_sets.inc'*)
IMPLEMENTATION OF cg_expr_sets;

FUNCTION CodegenSetMember(ordinal_val, set_val: ADRMEM): ADRMEM;
{ Lowers ordinal IN set to a bit test, mirroring codegen_set_member. }
VAR
  slot: ADRMEM;
  ord64, word_idx, bit_idx, mask, word_val, anded: ADRMEM;
  gep_idx, word_ptr: ADRMEM;
BEGIN
  slot := EntryAlloca(setty, '');
  LLVMBuildStore(builder, set_val, slot);
  ord64 := LLVMBuildSExt(builder, ordinal_val, i64ty, MakeCStr(''));
  word_idx := LLVMBuildUDiv(builder, ord64, LLVMConstInt(i64ty, 64, 0), MakeCStr(''));
  bit_idx := LLVMBuildURem(builder, ord64, LLVMConstInt(i64ty, 64, 0), MakeCStr(''));
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, word_idx);
  word_ptr := LLVMBuildGEP2(builder, setty, slot, gep_idx, 2, MakeCStr(''));
  word_val := LLVMBuildLoad2(builder, i64ty, word_ptr, MakeCStr(''));
  mask := LLVMBuildShl(builder, LLVMConstInt(i64ty, 1, 0), bit_idx, MakeCStr(''));
  anded := LLVMBuildAnd(builder, word_val, mask, MakeCStr(''));
  CodegenSetMember := LLVMBuildICmp(builder, LLVMIntNE, anded, LLVMConstInt(i64ty, 0, 0), MakeCStr(''));
END;

FUNCTION CodegenSetBinOp(op: Str255; lval, rval: ADRMEM): ADRMEM;
{ Extracts all 4 words of each operand via compile-time-constant-index
  ExtractValue (no loop needed, unlike the constructor/membership paths
  above), combines them per-word, and (for +/-/*) reassembles a result set
  via InsertValue starting from an all-zero aggregate. Sets last_val_tk
  itself: TK_BOOLEAN for the comparison operators, EnsureGenericSetType
  for the set-valued ones. }
VAR
  lw, rw, res_words: ARRAY [0..3] OF ADRMEM;
  i: INTEGER;
  res: ADRMEM;
  eq_all, sub_all, wc: ADRMEM;
  le_ok, ge_ok, eqv: ADRMEM;
BEGIN
  FOR i := 0 TO 3 DO
  BEGIN
    lw[i] := LLVMBuildExtractValue(builder, lval, i, MakeCStr(''));
    rw[i] := LLVMBuildExtractValue(builder, rval, i, MakeCStr(''));
  END;

  IF op = 'PLUS' THEN
  BEGIN
    res := LLVMConstNull(setty);
    FOR i := 0 TO 3 DO
      res := LLVMBuildInsertValue(builder, res, LLVMBuildOr(builder, lw[i], rw[i], MakeCStr('')), i, MakeCStr(''));
    CodegenSetBinOp := res;
    last_val_tk := EnsureGenericSetType;
  END
  ELSE IF op = 'MUL' THEN
  BEGIN
    res := LLVMConstNull(setty);
    FOR i := 0 TO 3 DO
      res := LLVMBuildInsertValue(builder, res, LLVMBuildAnd(builder, lw[i], rw[i], MakeCStr('')), i, MakeCStr(''));
    CodegenSetBinOp := res;
    last_val_tk := EnsureGenericSetType;
  END
  ELSE IF op = 'MINUS' THEN
  BEGIN
    res := LLVMConstNull(setty);
    FOR i := 0 TO 3 DO
    BEGIN
      wc := LLVMBuildNot(builder, rw[i], MakeCStr(''));
      res := LLVMBuildInsertValue(builder, res, LLVMBuildAnd(builder, lw[i], wc, MakeCStr('')), i, MakeCStr(''));
    END;
    CodegenSetBinOp := res;
    last_val_tk := EnsureGenericSetType;
  END
  ELSE IF (op = 'EQ') OR (op = 'NEQ') THEN
  BEGIN
    eq_all := LLVMBuildICmp(builder, LLVMIntEQ, lw[0], rw[0], MakeCStr(''));
    FOR i := 1 TO 3 DO
      eq_all := LLVMBuildAnd(builder, eq_all, LLVMBuildICmp(builder, LLVMIntEQ, lw[i], rw[i], MakeCStr('')), MakeCStr(''));
    IF op = 'EQ' THEN CodegenSetBinOp := eq_all
    ELSE CodegenSetBinOp := LLVMBuildXor(builder, eq_all, LLVMConstInt(i1ty, 1, 0), MakeCStr(''));
    last_val_tk := TK_BOOLEAN;
  END
  ELSE IF (op = 'LE') OR (op = 'LT') OR (op = 'GE') OR (op = 'GT') THEN
  BEGIN
    { subset(A, B): every bit in A is also in B, i.e. (A AND NOT B) = 0 for
      every word. LE/LT test subset(left, right); GE/GT test the reverse. }
    IF (op = 'LE') OR (op = 'LT') THEN
    BEGIN
      sub_all := LLVMBuildICmp(builder, LLVMIntEQ, LLVMBuildAnd(builder, lw[0], LLVMBuildNot(builder, rw[0], MakeCStr('')), MakeCStr('')), LLVMConstInt(i64ty, 0, 0), MakeCStr(''));
      FOR i := 1 TO 3 DO
      BEGIN
        wc := LLVMBuildICmp(builder, LLVMIntEQ, LLVMBuildAnd(builder, lw[i], LLVMBuildNot(builder, rw[i], MakeCStr('')), MakeCStr('')), LLVMConstInt(i64ty, 0, 0), MakeCStr(''));
        sub_all := LLVMBuildAnd(builder, sub_all, wc, MakeCStr(''));
      END;
    END
    ELSE
    BEGIN
      sub_all := LLVMBuildICmp(builder, LLVMIntEQ, LLVMBuildAnd(builder, rw[0], LLVMBuildNot(builder, lw[0], MakeCStr('')), MakeCStr('')), LLVMConstInt(i64ty, 0, 0), MakeCStr(''));
      FOR i := 1 TO 3 DO
      BEGIN
        wc := LLVMBuildICmp(builder, LLVMIntEQ, LLVMBuildAnd(builder, rw[i], LLVMBuildNot(builder, lw[i], MakeCStr('')), MakeCStr('')), LLVMConstInt(i64ty, 0, 0), MakeCStr(''));
        sub_all := LLVMBuildAnd(builder, sub_all, wc, MakeCStr(''));
      END;
    END;
    IF (op = 'LE') OR (op = 'GE') THEN
      CodegenSetBinOp := sub_all
    ELSE
    BEGIN
      eqv := LLVMBuildICmp(builder, LLVMIntEQ, lw[0], rw[0], MakeCStr(''));
      FOR i := 1 TO 3 DO
        eqv := LLVMBuildAnd(builder, eqv, LLVMBuildICmp(builder, LLVMIntEQ, lw[i], rw[i], MakeCStr('')), MakeCStr(''));
      CodegenSetBinOp := LLVMBuildAnd(builder, sub_all, LLVMBuildXor(builder, eqv, LLVMConstInt(i1ty, 1, 0), MakeCStr('')), MakeCStr(''));
    END;
    last_val_tk := TK_BOOLEAN;
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unsupported SET operator: ', op);
    CodegenSetBinOp := NIL;
  END;
END;

BEGIN
END.
