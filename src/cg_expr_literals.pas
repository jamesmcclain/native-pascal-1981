{ Implementations for cg_expr_literals. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_expr_literals.inc'*)
IMPLEMENTATION OF cg_expr_literals;

PROCEDURE CodegenLStringLiteralAssign(dest_addr: ADRMEM; dest_tid: INTEGER; s: Str255);
VAR
  i, len: INTEGER;
  cap: INTEGER32;
  gep_idx, elem_ptr: ADRMEM;
BEGIN
  len := ORD(s[0]);
  cap := types[dest_tid].hi;
  IF len > cap THEN
    AbortWith('codegen: string literal too long for LSTRING capacity');
  FOR i := 1 TO len DO
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, i, 0));
    elem_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(dest_tid), dest_addr, gep_idx, 2, MakeCStr(''));
    LLVMBuildStore(builder, LLVMConstInt(i8ty, ORD(s[i]), 0), elem_ptr);
  END;
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  elem_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(dest_tid), dest_addr, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i8ty, len, 0), elem_ptr);
END;

PROCEDURE CodegenStringLiteralAssign(dest_addr: ADRMEM; dest_tid: INTEGER; s: Str255);
VAR
  i, len: INTEGER;
  gep_idx, elem_ptr: ADRMEM;
BEGIN
  len := ORD(s[0]);
  IF len <> types[dest_tid].hi THEN
    AbortWith('codegen: string literal length does not match STRING capacity');
  FOR i := 1 TO len DO
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, i - 1, 0));
    elem_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(dest_tid), dest_addr, gep_idx, 2, MakeCStr(''));
    LLVMBuildStore(builder, LLVMConstInt(i8ty, ORD(s[i]), 0), elem_ptr);
  END;
END;

BEGIN
END.
