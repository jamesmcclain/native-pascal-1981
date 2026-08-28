{ Implementations for cg_expr_support. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_expr_support.inc'*)
IMPLEMENTATION OF cg_expr_support;

FUNCTION VariadicPromote(v: ADRMEM; tk: INTEGER; name: Str255): ADRMEM;
BEGIN
  IF IsAggregateTk(tk) THEN
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

FUNCTION LaunchI64(v: ADRMEM; tk: INTEGER): ADRMEM;
BEGIN
  IF (tk = TK_INTEGER64) OR (tk = TK_WORD64) THEN LaunchI64 := v
  ELSE IF IsUnsignedWordTk(tk) THEN LaunchI64 := LLVMBuildZExt(builder, v, i64ty, MakeCStr(''))
  ELSE LaunchI64 := LLVMBuildSExt(builder, v, i64ty, MakeCStr(''));
END;

BEGIN
END.
