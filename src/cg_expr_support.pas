{ Implementations for cg_expr_support. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_expr_support.inc'*)
IMPLEMENTATION OF cg_expr_support;

FUNCTION VariadicPromote(v: ADRMEM; tk: INTEGER; name: Str255): ADRMEM;
BEGIN
  IF ExposesHostDescriptor(tk) THEN
  BEGIN
    AbortWith2('codegen: a super-array descriptor cannot be a C variadic argument: ', name);
    VariadicPromote := v;
  END
  ELSE IF IsAggregateTk(tk) THEN
  BEGIN
    AbortWith2('codegen: an aggregate cannot be a variadic argument, calling: ', name);
    VariadicPromote := v;
  END
  ELSE IF tk = TK_REAL32 THEN
    VariadicPromote := LLVMBuildFPExt(builder, v, dblty, MakeCStr(''))
  ELSE IF tk = TK_BOOLEAN THEN
    VariadicPromote := LLVMBuildZExt(builder, v, i32ty, MakeCStr(''))
  ELSE IF (tk = TK_CHAR) OR (tk = TK_INTEGER8) OR (tk = TK_WORD8)
          OR (tk = TK_INTEGER) OR (tk = TK_WORD) THEN
  BEGIN
    IF IsUnsignedWordTk(tk) THEN
      VariadicPromote := LLVMBuildZExt(builder, v, i32ty, MakeCStr(''))
    ELSE
      VariadicPromote := LLVMBuildSExt(builder, v, i32ty, MakeCStr(''));
  END
  ELSE
    VariadicPromote := v;
END;

FUNCTION MakeArgs1(v: ADRMEM): ADRMEM;
VAR
  a: ADRMEM;
BEGIN
  a := AllocPtrArray(1);
  SetPtrArrayElem(a, 0, v);
  MakeArgs1 := a;
END;

FUNCTION CodegenHostDeviceIndex(nm: Str255): ADRMEM;
VAR
  gv_name: Str255;
  gv: ADRMEM;
BEGIN
  IF nm = 'THREADIDX_X' THEN gv_name := '__pas_tid_x'
  ELSE IF nm = 'THREADIDX_Y' THEN gv_name := '__pas_tid_y'
  ELSE IF nm = 'THREADIDX_Z' THEN gv_name := '__pas_tid_z'
  ELSE IF nm = 'BLOCKIDX_X' THEN gv_name := '__pas_ctaid_x'
  ELSE IF nm = 'BLOCKIDX_Y' THEN gv_name := '__pas_ctaid_y'
  ELSE IF nm = 'BLOCKIDX_Z' THEN gv_name := '__pas_ctaid_z'
  ELSE IF nm = 'BLOCKDIM_X' THEN gv_name := '__pas_ntid_x'
  ELSE IF nm = 'BLOCKDIM_Y' THEN gv_name := '__pas_ntid_y'
  ELSE IF nm = 'BLOCKDIM_Z' THEN gv_name := '__pas_ntid_z'
  ELSE IF nm = 'GRIDDIM_X' THEN gv_name := '__pas_nctaid_x'
  ELSE IF nm = 'GRIDDIM_Y' THEN gv_name := '__pas_nctaid_y'
  ELSE IF nm = 'GRIDDIM_Z' THEN gv_name := '__pas_nctaid_z'
  ELSE AbortWith2('codegen: unknown device index builtin: ', nm);
  gv := LLVMGetNamedGlobal(modl, MakeCStr(gv_name));
  IF gv = NIL THEN
  BEGIN
    gv := LLVMAddGlobal(modl, i32ty, MakeCStr(gv_name));
    LLVMSetLinkage(gv, 0);
    LLVMSetThreadLocal(gv, 1);
  END;
  CodegenHostDeviceIndex := LLVMBuildLoad2(builder, i32ty, gv, MakeCStr(''));
  last_val_tk := TK_INTEGER32;
END;

FUNCTION CodegenDeviceIndex(nm: Str255): ADRMEM;
VAR
  intrinsic_name: Str255;
  fnty, fn: ADRMEM;
BEGIN
  IF NOT is_nvptx_device THEN
  BEGIN
    IF NOT is_device_compiland THEN
      AbortWith2('codegen: device index builtin requires DEVICE code: ', nm);
    CodegenDeviceIndex := CodegenHostDeviceIndex(nm);
  END
  ELSE
  BEGIN
    IF nm = 'THREADIDX_X' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.tid.x'
    ELSE IF nm = 'THREADIDX_Y' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.tid.y'
    ELSE IF nm = 'THREADIDX_Z' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.tid.z'
    ELSE IF nm = 'BLOCKIDX_X' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.ctaid.x'
    ELSE IF nm = 'BLOCKIDX_Y' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.ctaid.y'
    ELSE IF nm = 'BLOCKIDX_Z' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.ctaid.z'
    ELSE IF nm = 'BLOCKDIM_X' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.ntid.x'
    ELSE IF nm = 'BLOCKDIM_Y' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.ntid.y'
    ELSE IF nm = 'BLOCKDIM_Z' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.ntid.z'
    ELSE IF nm = 'GRIDDIM_X' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.nctaid.x'
    ELSE IF nm = 'GRIDDIM_Y' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.nctaid.y'
    ELSE IF nm = 'GRIDDIM_Z' THEN intrinsic_name := 'llvm.nvvm.read.ptx.sreg.nctaid.z'
    ELSE AbortWith2('codegen: unknown device index builtin: ', nm);
    fnty := LLVMFunctionType(i32ty, NIL, 0, 0);
    fn := LLVMGetNamedFunction(modl, MakeCStr(intrinsic_name));
    IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr(intrinsic_name), fnty);
    CodegenDeviceIndex := LLVMBuildCall2(builder, fnty, fn, NIL, 0, MakeCStr(''));
    last_val_tk := TK_INTEGER32;
  END;
END;

{ ======================= WRITE-style scalar formatting ==================== }

{ The scalar WRITE formatter and the ordinal name tables sit here, below the
  expression dispatcher, so cg_io's WRITE/READ lowering and cg_expr's ENCODE
  lowering share one printf format vocabulary. }

FUNCTION EnumNameTable(tid: INTEGER): ADRMEM;
{ Build the const-char* name vector used by the extended enum readers and
  writer. The enum AST remains alive for the whole compilation, so TypeRec
  can retain its values array without copying names into another fixed table. }
VAR
  values_arr, tbl, gep_idx, slot: ADRMEM;
  i, count: INTEGER32;
  member_name: Str255;
BEGIN
  values_arr := types[tid].enum_values;
  IF values_arr = NIL THEN AbortWith('codegen: enum member names are unavailable');
  count := ArrSize(values_arr);
  tbl := EntryAlloca(LLVMArrayType(i8ptrty, count), 'enumnames');
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  FOR i := 0 TO count - 1 DO
  BEGIN
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, i, 0));
    slot := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, count), tbl,
                          gep_idx, 2, MakeCStr(''));
    member_name := CStrToStr255(cJSON_GetStringValue(ArrItem(values_arr, i)));
    LLVMBuildStore(builder,
      LLVMBuildGlobalStringPtr(builder, MakeCStr(member_name), MakeCStr('enumname')),
      slot);
  END;
  EnumNameTable := LLVMBuildBitCast(builder, tbl,
                                    LLVMPointerType(i8ptrty, 0), MakeCStr(''));
END;

PROCEDURE EmitScalarWriteArgHost(in_v: ADRMEM; tid: INTEGER; have_width, have_prec: BOOLEAN;
  width_val, prec_val: ADRMEM; VAR fmt: Str255; vals: ADRMEM; VAR vi: INTEGER32);
{ The generic INTEGER/WORD/REAL/CHAR/BOOLEAN WRITE-argument formatter,
  shared by every WRITE argument shape that isn't itself string-typed
  (non-string Identifier, Designator, and any other expression kind).
  Value parameters can't be reassigned in this dialect (mirrors the
  reference's own codegen_assign_stmt restriction), hence out_v as a
  separate local rather than reusing in_v. }
VAR
  out_v: ADRMEM;
  handled_own_args: BOOLEAN;
  is_true, bool_str, call_args: ADRMEM;
BEGIN
  out_v := in_v;
  handled_own_args := FALSE;
  IF TypeKind(tid) = TK_INTEGER THEN
  BEGIN
    out_v := LLVMBuildSExt(builder, in_v, i32ty, MakeCStr(''));
    IF have_width THEN CONCAT(fmt, '%*d') ELSE CONCAT(fmt, '%d');
  END
  ELSE IF tid = TK_WORD THEN
  BEGIN
    out_v := LLVMBuildZExt(builder, in_v, i32ty, MakeCStr(''));
    IF have_width THEN CONCAT(fmt, '%*u') ELSE CONCAT(fmt, '%u');
  END
  ELSE IF tid = TK_INTEGER8 THEN
  BEGIN
    out_v := LLVMBuildSExt(builder, in_v, i32ty, MakeCStr(''));
    IF have_width THEN CONCAT(fmt, '%*d') ELSE CONCAT(fmt, '%d');
  END
  ELSE IF tid = TK_WORD8 THEN
  BEGIN
    out_v := LLVMBuildZExt(builder, in_v, i32ty, MakeCStr(''));
    IF have_width THEN CONCAT(fmt, '%*u') ELSE CONCAT(fmt, '%u');
  END
  ELSE IF tid = TK_INTEGER32 THEN
  BEGIN
    IF have_width THEN CONCAT(fmt, '%*d') ELSE CONCAT(fmt, '%d');
  END
  ELSE IF tid = TK_WORD32 THEN
  BEGIN
    IF have_width THEN CONCAT(fmt, '%*u') ELSE CONCAT(fmt, '%u');
  END
  ELSE IF tid = TK_INTEGER64 THEN
  BEGIN
    IF have_width THEN CONCAT(fmt, '%*lld') ELSE CONCAT(fmt, '%lld');
  END
  ELSE IF tid = TK_WORD64 THEN
  BEGIN
    IF have_width THEN CONCAT(fmt, '%*llu') ELSE CONCAT(fmt, '%llu');
  END
  ELSE IF (tid = TK_REAL) OR (tid = TK_REAL32) THEN
  BEGIN
    IF tid = TK_REAL32 THEN out_v := LLVMBuildFPExt(builder, in_v, dblty, MakeCStr(''));
    IF have_prec THEN
    BEGIN
      CONCAT(fmt, '%*.*f');
      IF have_width THEN SetPtrArrayElem(vals, vi, width_val)
      ELSE SetPtrArrayElem(vals, vi, LLVMConstInt(i32ty, 14, 0));
      vi := vi + 1;
      SetPtrArrayElem(vals, vi, prec_val);
      vi := vi + 1;
    END
    ELSE IF have_width THEN
    BEGIN
      CONCAT(fmt, '%*E');
      SetPtrArrayElem(vals, vi, width_val);
      vi := vi + 1;
    END
    ELSE
      CONCAT(fmt, '%14.7E');
    SetPtrArrayElem(vals, vi, out_v);
    vi := vi + 1;
    handled_own_args := TRUE;
  END
  ELSE IF TypeKind(tid) = TK_CHAR THEN
  BEGIN
    IF have_width THEN CONCAT(fmt, '%*c') ELSE CONCAT(fmt, '%c');
  END
  ELSE IF TypeKind(tid) = TK_BOOLEAN THEN
  BEGIN
    is_true := LLVMBuildICmp(builder, LLVMIntNE, in_v, LLVMConstInt(i1ty, 0, 0), MakeCStr(''));
    bool_str := LLVMBuildSelect(builder, is_true,
      LLVMBuildGlobalStringPtr(builder, MakeCStr('TRUE'), MakeCStr('booltrue')),
      LLVMBuildGlobalStringPtr(builder, MakeCStr('FALSE'), MakeCStr('boolfalse')),
      MakeCStr(''));
    out_v := bool_str;
    IF have_width THEN CONCAT(fmt, '%*s') ELSE CONCAT(fmt, '%s');
  END
  ELSE IF TypeKind(tid) = TK_ENUM THEN
  BEGIN
    IF active_features.symbolic_enum_io THEN
    BEGIN
      call_args := AllocPtrArray(3);
      SetPtrArrayElem(call_args, 0, in_v);
      SetPtrArrayElem(call_args, 1, EnumNameTable(tid));
      SetPtrArrayElem(call_args, 2, LLVMConstInt(i32ty, types[tid].hi + 1, 0));
      out_v := LLVMBuildCall2(builder, enum_write_token_fnty,
                              enum_write_token_fn, call_args, 3, MakeCStr('enumtoken'));
      IF have_width THEN CONCAT(fmt, '%*s') ELSE CONCAT(fmt, '%s');
    END
    ELSE
    BEGIN
      { Vintage enumerated values use their numeric ordinal. }
      IF have_width THEN CONCAT(fmt, '%*d') ELSE CONCAT(fmt, '%d');
    END;
  END
  ELSE IF (TypeKind(tid) = TK_POINTER) OR (tid = TK_ADRMEM) THEN
  BEGIN
    IF IsHostDescriptor(tid) THEN
      AbortWith('codegen: numeric WRITE of a super-array descriptor is unsupported; use UNSAFERAW');
    { The manual reads pointer variables as numbers, in an
      implementation-defined format such that writing then reading
      preserves the value (13620-13623); this toolchain's format is
      unsigned decimal, matched by runtime's pas_read_ptr. }
    out_v := LLVMBuildPtrToInt(builder, in_v, i64ty, MakeCStr(''));
    IF have_width THEN CONCAT(fmt, '%*llu') ELSE CONCAT(fmt, '%llu');
  END
  ELSE
    AbortWith('codegen: unsupported WRITE argument type');
  IF NOT handled_own_args THEN
  BEGIN
    IF have_width THEN
    BEGIN
      SetPtrArrayElem(vals, vi, width_val);
      vi := vi + 1;
    END;
    SetPtrArrayElem(vals, vi, out_v);
    vi := vi + 1;
  END;
END;

PROCEDURE EmitScalarWriteArg(in_v: ADRMEM; tid: INTEGER; have_width, have_prec: BOOLEAN;
  width_val, prec_val: ADRMEM; VAR fmt: Str255; vals: ADRMEM; VAR vi: INTEGER32);
{ EmitScalarWriteArgHost on a subrange's host, so a WORD subrange value
  (NEW-32) is written unsigned and an INTEGER32 one in full. }
BEGIN
  EmitScalarWriteArgHost(in_v, SubrangeBaseTid(tid), have_width, have_prec,
    width_val, prec_val, fmt, vals, vi);
END;

FUNCTION BoolNameTable: ADRMEM;
{ A stack-built two-slot const-char* table holding "FALSE" then "TRUE" --
  the name list pas_read_enum_name matches BOOLEAN input against, so a
  BOOLEAN can be read by ordinal number or by identifier name
  (case-insensitively), exactly the union the manual allows (13610-13618). }
VAR
  tbl, gep_idx, slot: ADRMEM;
BEGIN
  tbl := EntryAlloca(LLVMArrayType(i8ptrty, 2), 'boolnames');
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  slot := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, 2), tbl, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMBuildGlobalStringPtr(builder, MakeCStr('FALSE'), MakeCStr('boolname')), slot);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  slot := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, 2), tbl, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMBuildGlobalStringPtr(builder, MakeCStr('TRUE'), MakeCStr('boolname')), slot);
  BoolNameTable := LLVMBuildBitCast(builder, tbl, LLVMPointerType(i8ptrty, 0), MakeCStr(''));
END;

PROCEDURE SetOrdinalBoundArgs(call_args: ADRMEM; at, tid: INTEGER);
{ Store the lo, hi ordinal bounds an enum or BOOLEAN reader accepts into
  call_args[at] and call_args[at + 1]: a subrange's declared bounds, else
  the whole type. Names tables always span the host type, so a subrange
  that starts above zero still indexes them by ordinal. }
VAR
  lo, hi: INTEGER32;
BEGIN
  IF tid >= 14 THEN
  BEGIN
    lo := types[tid].lo;
    hi := types[tid].hi;
  END
  ELSE
  BEGIN
    lo := 0;
    hi := 1;
  END;
  SetPtrArrayElem(call_args, at, LLVMConstInt(i32ty, lo, 0));
  SetPtrArrayElem(call_args, at + 1, LLVMConstInt(i32ty, hi, 0));
END;

FUNCTION LaunchI64(v: ADRMEM; tk: INTEGER): ADRMEM;
BEGIN
  IF (tk = TK_INTEGER64) OR (tk = TK_WORD64) THEN LaunchI64 := v
  ELSE IF IsUnsignedWordTk(tk) THEN LaunchI64 := LLVMBuildZExt(builder, v, i64ty, MakeCStr(''))
  ELSE LaunchI64 := LLVMBuildSExt(builder, v, i64ty, MakeCStr(''));
END;

BEGIN
END.
