{ Implementations for cg_io. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
(*$INCLUDE:'cg_expr.inc'*)
(*$INCLUDE:'cg_io.inc'*)
IMPLEMENTATION OF cg_io;

{ ============================ WRITE/WRITELN =============================== }

{ ============================ WRITE/WRITELN =============================== }

FUNCTION EvalPrintfIntArg(node: ADRMEM): ADRMEM;
{ Evaluate a WriteArg width/precision expression and coerce it to the C int
  (i32) that printf's `*` specifier expects, mirroring the Python
  reference's coerce_printf_int (types_map.py): native INTEGER is 16-bit, so
  sign-extend it to i32; anything already i32 passes through unchanged. }
VAR
  v: ADRMEM;
BEGIN
  v := CodegenExpr(node);
  IF last_val_tk = TK_INTEGER THEN
    v := LLVMBuildSExt(builder, v, i32ty, MakeCStr(''));
  EvalPrintfIntArg := v;
END;

PROCEDURE EmitStringWriteArg(addr: ADRMEM; tid: INTEGER; have_width: BOOLEAN; width_val: ADRMEM;
  VAR fmt: Str255; vals: ADRMEM; VAR vi: INTEGER32);
{ Appends a %.*s (or %*.*s with a width) format spec plus its (len, chars)
  value pair for an LSTRING/STRING value already resolved to an address --
  shared by the bare-Identifier and Designator (array/field selector) WRITE
  argument paths, which differ only in how they got that address. }
VAR
  gep_idx, len_ptr, len_val, chars_ptr: ADRMEM;
BEGIN
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
  ELSE
  BEGIN
    len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
  END;
  IF have_width THEN
  BEGIN
    CONCAT(fmt, '%*.*s');
    SetPtrArrayElem(vals, vi, width_val);
    vi := vi + 1;
  END
  ELSE
    CONCAT(fmt, '%.*s');
  SetPtrArrayElem(vals, vi, len_val);
  vi := vi + 1;
  SetPtrArrayElem(vals, vi, chars_ptr);
  vi := vi + 1;
END;

PROCEDURE EmitScalarWriteArg(in_v: ADRMEM; tid: INTEGER; have_width, have_prec: BOOLEAN;
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
  is_true, bool_str: ADRMEM;
BEGIN
  out_v := in_v;
  handled_own_args := FALSE;
  IF tid = TK_INTEGER THEN
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
  ELSE IF tid = TK_CHAR THEN
  BEGIN
    IF have_width THEN CONCAT(fmt, '%*c') ELSE CONCAT(fmt, '%c');
  END
  ELSE IF tid = TK_BOOLEAN THEN
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
    { An enumerated value writes as its ordinal number -- the vintage
      default (the reference's symbolic-enum-io feature is off by default).
      The value is already i32, the enum's storage, so no extend. }
    IF have_width THEN CONCAT(fmt, '%*d') ELSE CONCAT(fmt, '%d');
  END
  ELSE IF TypeKind(tid) = TK_POINTER THEN
  BEGIN
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

FUNCTION GetDefaultInputFcbPtr: ADRMEM;
{ Loads the predeclared INPUT/OUTPUT FCBs (registered unconditionally for
  every PROGRAM by RegisterPredeclaredFiles) and lazily binds them to real
  stdin/stdout via pas_file_attach_std, mirroring the reference's
  _file_selector_fcb attach-on-first-use behavior. Returns the INPUT FCB*. }
VAR
  in_fcb, out_fcb, call_args, discard: ADRMEM;
BEGIN
  in_fcb := LoadFileFcbPtr('INPUT');
  out_fcb := LoadFileFcbPtr('OUTPUT');
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, in_fcb);
  SetPtrArrayElem(call_args, 1, out_fcb);
  discard := LLVMBuildCall2(builder, file_attach_std_fnty, file_attach_std_fn, call_args, 2, MakeCStr(''));
  GetDefaultInputFcbPtr := in_fcb;
END;

PROCEDURE CodegenWriteArgs(args: ADRMEM; newline: BOOLEAN);
VAR
  nargs, i, start_idx: INTEGER32;
  fmt: Str255;
  arg_node, expr, width_node, prec_node: ADRMEM;
  vals: ADRMEM;
  v, width_val, prec_val: ADRMEM;
  strval: Str255;
  call_ret: ADRMEM;
  vi: INTEGER32;
  addr, fcb_ptr, fmt_ptr: ADRMEM;
  lstr_tid: INTEGER;
  symi: INTEGER32;
  is_lstring, is_string, have_width, have_prec, using_file: BOOLEAN;
BEGIN
  nargs := ArrSize(args);
  fmt := '';
  vals := AllocPtrArray(nargs * 3 + 2);
  { A leading WriteArg naming a TEXT file variable selects the destination
    instead of being a data argument -- WRITE(F, ...) per the manual --
    routing the whole call through pas_write_fmt against that file's FCB
    instead of printf to stdout. When present, vals[0]/[1] hold the fcb
    pointer and format string (pas_write_fmt's own leading params); data
    arguments start one slot later than the file-less case to make room. }
  start_idx := 0;
  using_file := FALSE;
  IF nargs > 0 THEN
  BEGIN
    arg_node := ArrItem(args, 0);
    expr := GetObj(arg_node, 'expr');
    IF NodeType(expr) = 'Identifier' THEN
    BEGIN
      symi := LookupSym(GetStr(expr, 'name'));
      IF (symi <> 0) AND (TypeKind(symbols[symi].tk) = TK_FILE) THEN
      BEGIN
        fcb_ptr := LoadFileFcbPtr(GetStr(expr, 'name'));
        using_file := TRUE;
        start_idx := 1;
      END;
    END;
  END;
  IF using_file THEN vi := 2 ELSE vi := 1;
  FOR i := start_idx TO nargs - 1 DO
  BEGIN
    arg_node := ArrItem(args, i);
    IF NodeType(arg_node) <> 'WriteArg' THEN
      AbortWith('codegen: expected WriteArg node');
    expr := GetObj(arg_node, 'expr');
    width_node := GetObjOrNil(arg_node, 'width');
    prec_node := GetObjOrNil(arg_node, 'precision');
    { Precision is only ever consulted for REAL/REAL32's width+precision ->
      %*.*f path below, matching the Python reference's faithful-1981
      default (it ignores string precision and never consults precision
      at all for the generic int/char/boolean case). }
    have_width := width_node <> NIL;
    IF have_width THEN width_val := EvalPrintfIntArg(width_node);
    have_prec := prec_node <> NIL;
    IF have_prec THEN prec_val := EvalPrintfIntArg(prec_node);
    is_lstring := FALSE;
    is_string := FALSE;
    IF NodeType(expr) = 'StringLiteral' THEN
    BEGIN
      strval := DecodeStringLiteral(GetStr(expr, 'value'));
      v := LLVMBuildGlobalStringPtr(builder, MakeCStr(strval), MakeCStr('str'));
      IF have_width THEN
      BEGIN
        CONCAT(fmt, '%*s');
        SetPtrArrayElem(vals, vi, width_val);
        vi := vi + 1;
      END
      ELSE
        CONCAT(fmt, '%s');
      SetPtrArrayElem(vals, vi, v);
      vi := vi + 1;
    END
    ELSE IF NodeType(expr) = 'Identifier' THEN
    BEGIN
      symi := LookupSym(GetStr(expr, 'name'));
      IF symi <> 0 THEN
      BEGIN
        IF TypeKind(symbols[symi].tk) = TK_LSTRING THEN
        BEGIN
          is_lstring := TRUE;
          addr := symbols[symi].llvm_val;
          lstr_tid := symbols[symi].tk;
        END
        ELSE IF TypeKind(symbols[symi].tk) = TK_STRING THEN
        BEGIN
          is_string := TRUE;
          addr := symbols[symi].llvm_val;
          lstr_tid := symbols[symi].tk;
        END;
      END;
      IF is_lstring OR is_string THEN
        EmitStringWriteArg(addr, lstr_tid, have_width, width_val, fmt, vals, vi)
      ELSE
      BEGIN
        v := CodegenExpr(expr);
        EmitScalarWriteArg(v, last_val_tk, have_width, have_prec, width_val, prec_val, fmt, vals, vi);
      END;
    END
    ELSE IF NodeType(expr) = 'Designator' THEN
    BEGIN
      { A single ComputeDesignatorAddress call -- reused for both the
        string and scalar cases below -- so an array-index/field-selector
        chain with a side-effecting sub-expression is only ever evaluated
        once. }
      addr := ComputeDesignatorAddress(expr);
      lstr_tid := last_val_tk;
      IF (TypeKind(lstr_tid) = TK_LSTRING) OR (TypeKind(lstr_tid) = TK_STRING) THEN
        EmitStringWriteArg(addr, lstr_tid, have_width, width_val, fmt, vals, vi)
      ELSE
      BEGIN
        v := LLVMBuildLoad2(builder, LLVMTypeForTk(lstr_tid), addr, MakeCStr(''));
        EmitScalarWriteArg(v, lstr_tid, have_width, have_prec, width_val, prec_val, fmt, vals, vi);
      END;
    END
    ELSE
    BEGIN
      v := CodegenExpr(expr);
      EmitScalarWriteArg(v, last_val_tk, have_width, have_prec, width_val, prec_val, fmt, vals, vi);
    END;
  END;
  IF newline THEN AppendChar(fmt, CHR(10));
  fmt_ptr := LLVMBuildGlobalStringPtr(builder, MakeCStr(fmt), MakeCStr('fmt'));
  IF using_file THEN
  BEGIN
    SetPtrArrayElem(vals, 0, fcb_ptr);
    SetPtrArrayElem(vals, 1, fmt_ptr);
    call_ret := LLVMBuildCall2(builder, write_fmt_fnty, write_fmt_fn, vals, vi, MakeCStr('callwritefmt'));
  END
  ELSE
  BEGIN
    SetPtrArrayElem(vals, 0, fmt_ptr);
    call_ret := LLVMBuildCall2(builder, printf_fnty, printf_fn, vals, vi, MakeCStr('callprintf'));
  END;
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

PROCEDURE CodegenReadStdinVar(addr: ADRMEM; tid: INTEGER);
{ Reads one value from stdin into `addr`, dispatching on `tid` -- the
  non-file subset of CodegenReadArgs's per-argument logic, factored out for
  CodegenProgramParameters (a non-FILE program-heading parameter is bound
  by reading it exactly like an ordinary bare READ, just under the
  command-line/keyboard stdin redirect runtime/cmdline.c sets up). }
VAR
  tmp32, loaded, call_args, buf_i8, cap, tmp64: ADRMEM;
BEGIN
  IF TypeKind(tid) = TK_INTEGER THEN
  BEGIN
    tmp32 := EntryAlloca(i32ty, '');
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, tmp32);
    loaded := LLVMBuildCall2(builder, read_int_fnty, read_int_fn, call_args, 1, MakeCStr(''));
    loaded := LLVMBuildLoad2(builder, i32ty, tmp32, MakeCStr(''));
    loaded := LLVMBuildTrunc(builder, loaded, i16ty, MakeCStr(''));
    LLVMBuildStore(builder, loaded, addr);
  END
  ELSE IF TypeKind(tid) = TK_WORD THEN
  BEGIN
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, addr);
    loaded := LLVMBuildCall2(builder, read_word_fnty, read_word_fn, call_args, 1, MakeCStr(''));
  END
  ELSE IF TypeKind(tid) = TK_REAL THEN
  BEGIN
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, addr);
    loaded := LLVMBuildCall2(builder, read_real_fnty, read_real_fn, call_args, 1, MakeCStr(''));
  END
  ELSE IF TypeKind(tid) = TK_CHAR THEN
  BEGIN
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, addr);
    loaded := LLVMBuildCall2(builder, read_char_fnty, read_char_fn, call_args, 1, MakeCStr(''));
  END
  ELSE IF TypeKind(tid) = TK_LSTRING THEN
  BEGIN
    buf_i8 := LLVMBuildBitCast(builder, addr, i8ptrty, MakeCStr(''));
    cap := LLVMConstInt(i32ty, types[tid].hi, 0);
    call_args := AllocPtrArray(2);
    SetPtrArrayElem(call_args, 0, buf_i8);
    SetPtrArrayElem(call_args, 1, cap);
    loaded := LLVMBuildCall2(builder, read_lstring_fnty, read_lstring_fn, call_args, 2, MakeCStr(''));
  END
  ELSE IF TypeKind(tid) = TK_STRING THEN
  BEGIN
    buf_i8 := LLVMBuildBitCast(builder, addr, i8ptrty, MakeCStr(''));
    cap := LLVMConstInt(i32ty, types[tid].hi, 0);
    call_args := AllocPtrArray(2);
    SetPtrArrayElem(call_args, 0, buf_i8);
    SetPtrArrayElem(call_args, 1, cap);
    loaded := LLVMBuildCall2(builder, read_string_fnty, read_string_fn, call_args, 2, MakeCStr(''));
  END
  ELSE IF TypeKind(tid) = TK_ENUM THEN
  BEGIN
    { Enumerated values read as a numeric ordinal -- the manual reads them
      as numbers, not names (13610-13618), and the reference does the same
      with symbolic-enum-io off. Storage is i32, matching pas_read_int's
      output width, so no conversion. }
    tmp32 := EntryAlloca(i32ty, '');
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, tmp32);
    loaded := LLVMBuildCall2(builder, read_int_fnty, read_int_fn, call_args, 1, MakeCStr(''));
    loaded := LLVMBuildLoad2(builder, i32ty, tmp32, MakeCStr(''));
    LLVMBuildStore(builder, loaded, addr);
  END
  ELSE IF TypeKind(tid) = TK_BOOLEAN THEN
  BEGIN
    { The manual reads a BOOLEAN as a number or by the TRUE/FALSE names
      (13610-13618); pas_read_enum_name against the FALSE/TRUE table
      accepts exactly that union. }
    tmp32 := EntryAlloca(i32ty, '');
    call_args := AllocPtrArray(3);
    SetPtrArrayElem(call_args, 0, tmp32);
    SetPtrArrayElem(call_args, 1, BoolNameTable);
    SetPtrArrayElem(call_args, 2, LLVMConstInt(i32ty, 2, 0));
    loaded := LLVMBuildCall2(builder, read_enum_name_fnty, read_enum_name_fn, call_args, 3, MakeCStr(''));
    loaded := LLVMBuildLoad2(builder, i32ty, tmp32, MakeCStr(''));
    loaded := LLVMBuildTrunc(builder, loaded, i1ty, MakeCStr(''));
    LLVMBuildStore(builder, loaded, addr);
  END
  ELSE IF TypeKind(tid) = TK_POINTER THEN
  BEGIN
    { Pointer-as-number read, the implementation-defined round-trip format
      shared with WRITE's pointer path (manual 13620-13623). }
    tmp64 := EntryAlloca(i64ty, '');
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, tmp64);
    loaded := LLVMBuildCall2(builder, read_ptr_fnty, read_ptr_fn, call_args, 1, MakeCStr(''));
    loaded := LLVMBuildLoad2(builder, i64ty, tmp64, MakeCStr(''));
    loaded := LLVMBuildIntToPtr(builder, loaded, i8ptrty, MakeCStr(''));
    LLVMBuildStore(builder, loaded, addr);
  END
  ELSE
    AbortWith('codegen: unsupported program-parameter type');
END;

PROCEDURE CodegenBindFileParameter(symi: INTEGER32);
{ Binds a FILE program-heading parameter's filename from the command line
  (or the keyboard, via the same redirect pas_arg_begin already set up),
  mirroring the reference's _bind_file_parameter: read the filename token
  as an LSTRING, then ASSIGN it to the file's own FCB so a later
  RESET/REWRITE opens it. }
CONST
  ARGNAME_CAP = 255;
VAR
  buf, buf_i8, gep_idx, name_ptr, length_val, call_args, fcb_ptr, discard: ADRMEM;
BEGIN
  buf := EntryAlloca(LLVMArrayType(i8ty, ARGNAME_CAP + 1), 'arg_filename');
  buf_i8 := LLVMBuildBitCast(builder, buf, i8ptrty, MakeCStr(''));
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, buf_i8);
  SetPtrArrayElem(call_args, 1, LLVMConstInt(i32ty, ARGNAME_CAP, 0));
  discard := LLVMBuildCall2(builder, read_lstring_fnty, read_lstring_fn, call_args, 2, MakeCStr(''));
  length_val := LLVMBuildLoad2(builder, i8ty, buf_i8, MakeCStr(''));
  length_val := LLVMBuildZExt(builder, length_val, i32ty, MakeCStr(''));
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  name_ptr := LLVMBuildGEP2(builder, LLVMArrayType(i8ty, ARGNAME_CAP + 1), buf, gep_idx, 2, MakeCStr(''));
  fcb_ptr := LoadFileFcbPtr(symbols[symi].name);
  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, fcb_ptr);
  SetPtrArrayElem(call_args, 1, name_ptr);
  SetPtrArrayElem(call_args, 2, length_val);
  discard := LLVMBuildCall2(builder, file_assign_fnty, file_assign_fn, call_args, 3, MakeCStr(''));
END;

PROCEDURE CodegenProgramParameters(root: ADRMEM);
{ Populates program-heading parameters from the command line, mirroring the
  reference's _codegen_program_parameters exactly (manual 13-5..13-7): each
  heading parameter other than INPUT/OUTPUT is read, in heading order, from
  successive command-line tokens (falling back to a "<name>: " keyboard
  prompt when a token is absent -- runtime/cmdline.c's pas_arg_begin). Must
  run after CodegenDeclList so every parameter's own symbol (and, for a
  FILE parameter, its FCB storage) already exists. }
VAR
  params, pname_item: ADRMEM;
  nparams, pi, position, symi: INTEGER32;
  pname, upname: Str255;
  bindable: BOOLEAN;
  name_ptr, call_args, discard: ADRMEM;
BEGIN
  params := GetObj(root, 'params');
  nparams := ArrSize(params);
  { Initialize the runtime for every PROGRAM. Native programs can use the
    raw command-line interface even when the heading has only INPUT/OUTPUT. }
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, main_argc_val);
  SetPtrArrayElem(call_args, 1, main_argv_val);
  discard := LLVMBuildCall2(builder, args_init_fnty, args_init_fn, call_args, 2, MakeCStr(''));

  bindable := FALSE;
  FOR pi := 0 TO nparams - 1 DO
  BEGIN
    pname := CStrToStr255(cJSON_GetStringValue(ArrItem(params, pi)));
    upname := UpperStr(pname);
    IF (upname <> 'INPUT') AND (upname <> 'OUTPUT') THEN bindable := TRUE;
  END;
  IF NOT bindable THEN RETURN;

  position := 0;
  FOR pi := 0 TO nparams - 1 DO
  BEGIN
    pname := CStrToStr255(cJSON_GetStringValue(ArrItem(params, pi)));
    upname := UpperStr(pname);
    IF (upname <> 'INPUT') AND (upname <> 'OUTPUT') THEN
    BEGIN
      symi := LookupSym(pname);
      IF symi <> 0 THEN
      BEGIN
        name_ptr := LLVMBuildGlobalStringPtr(builder, MakeCStr(pname), MakeCStr('argname'));
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, LLVMConstInt(i32ty, position, 0));
        SetPtrArrayElem(call_args, 1, name_ptr);
        discard := LLVMBuildCall2(builder, arg_begin_fnty, arg_begin_fn, call_args, 2, MakeCStr(''));
        IF TypeKind(symbols[symi].tk) = TK_FILE THEN
          CodegenBindFileParameter(symi)
        ELSE
          CodegenReadStdinVar(symbols[symi].llvm_val, symbols[symi].tk);
        discard := LLVMBuildCall2(builder, readln_skip_fnty, readln_skip_fn, NIL, 0, MakeCStr(''));
        discard := LLVMBuildCall2(builder, arg_end_fnty, arg_end_fn, NIL, 0, MakeCStr(''));
      END;
      position := position + 1;
    END;
  END;
END;

PROCEDURE CodegenReadArgs(args: ADRMEM; is_readln: BOOLEAN);
{ READ/READLN, both the bare-stdin form and the leading-TEXT-file-argument
  form (READ(F, ...)). Mirrors the reference's read-family codegen: each
  destination argument dispatches on its own resolved type to the matching
  pas_read_*/pas_fread_* runtime entry point (see runtime/pascalrt.h),
  which differ only in whether an FCB* leads the argument list. INTEGER is
  the one type needing a scratch conversion -- native INTEGER is 16-bit but
  every read runtime function fills a 32-bit int, matching the reference's
  own INTEGER32-based READ machinery. }
VAR
  nargs, i, symi: INTEGER32;
  start_idx: INTEGER32;
  arg0, argnode, addr, fcb_ptr, tmp32, loaded, call_args, buf_i8, cap, tmp64: ADRMEM;
  tid: INTEGER;
  using_file: BOOLEAN;
BEGIN
  nargs := ArrSize(args);
  start_idx := 0;
  using_file := FALSE;
  fcb_ptr := NIL;
  IF nargs > 0 THEN
  BEGIN
    arg0 := ArrItem(args, 0);
    IF NodeType(arg0) = 'Identifier' THEN
    BEGIN
      symi := LookupSym(GetStr(arg0, 'name'));
      IF (symi <> 0) AND (TypeKind(symbols[symi].tk) = TK_FILE) THEN
      BEGIN
        fcb_ptr := LoadFileFcbPtr(GetStr(arg0, 'name'));
        using_file := TRUE;
        start_idx := 1;
      END;
    END;
  END;

  FOR i := start_idx TO nargs - 1 DO
  BEGIN
    argnode := ArrItem(args, i);
    IF NodeType(argnode) = 'Identifier' THEN
    BEGIN
      symi := LookupSym(GetStr(argnode, 'name'));
      IF symi = 0 THEN AbortWith2('codegen: undefined variable: ', GetStr(argnode, 'name'));
      tid := symbols[symi].tk;
      addr := symbols[symi].llvm_val;
    END
    ELSE IF NodeType(argnode) = 'Designator' THEN
    BEGIN
      addr := ComputeDesignatorAddress(argnode);
      tid := last_val_tk;
    END
    ELSE
    BEGIN
      AbortWith('codegen: READ argument must be a designator');
      addr := NIL;
      tid := TK_UNKNOWN;
    END;

    IF TypeKind(tid) = TK_INTEGER THEN
    BEGIN
      tmp32 := EntryAlloca(i32ty, '');
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, tmp32);
        loaded := LLVMBuildCall2(builder, fread_int_fnty, fread_int_fn, call_args, 2, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(1);
        SetPtrArrayElem(call_args, 0, tmp32);
        loaded := LLVMBuildCall2(builder, read_int_fnty, read_int_fn, call_args, 1, MakeCStr(''));
      END;
      loaded := LLVMBuildLoad2(builder, i32ty, tmp32, MakeCStr(''));
      loaded := LLVMBuildTrunc(builder, loaded, i16ty, MakeCStr(''));
      LLVMBuildStore(builder, loaded, addr);
    END
    ELSE IF TypeKind(tid) = TK_WORD THEN
    BEGIN
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, addr);
        loaded := LLVMBuildCall2(builder, fread_word_fnty, fread_word_fn, call_args, 2, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(1);
        SetPtrArrayElem(call_args, 0, addr);
        loaded := LLVMBuildCall2(builder, read_word_fnty, read_word_fn, call_args, 1, MakeCStr(''));
      END;
    END
    ELSE IF TypeKind(tid) = TK_REAL THEN
    BEGIN
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, addr);
        loaded := LLVMBuildCall2(builder, fread_real_fnty, fread_real_fn, call_args, 2, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(1);
        SetPtrArrayElem(call_args, 0, addr);
        loaded := LLVMBuildCall2(builder, read_real_fnty, read_real_fn, call_args, 1, MakeCStr(''));
      END;
    END
    ELSE IF TypeKind(tid) = TK_CHAR THEN
    BEGIN
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, addr);
        loaded := LLVMBuildCall2(builder, fread_char_fnty, fread_char_fn, call_args, 2, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(1);
        SetPtrArrayElem(call_args, 0, addr);
        loaded := LLVMBuildCall2(builder, read_char_fnty, read_char_fn, call_args, 1, MakeCStr(''));
      END;
    END
    ELSE IF TypeKind(tid) = TK_LSTRING THEN
    BEGIN
      buf_i8 := LLVMBuildBitCast(builder, addr, i8ptrty, MakeCStr(''));
      cap := LLVMConstInt(i32ty, types[tid].hi, 0);
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(3);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, buf_i8);
        SetPtrArrayElem(call_args, 2, cap);
        loaded := LLVMBuildCall2(builder, fread_lstring_fnty, fread_lstring_fn, call_args, 3, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, buf_i8);
        SetPtrArrayElem(call_args, 1, cap);
        loaded := LLVMBuildCall2(builder, read_lstring_fnty, read_lstring_fn, call_args, 2, MakeCStr(''));
      END;
    END
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      buf_i8 := LLVMBuildBitCast(builder, addr, i8ptrty, MakeCStr(''));
      cap := LLVMConstInt(i32ty, types[tid].hi, 0);
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(3);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, buf_i8);
        SetPtrArrayElem(call_args, 2, cap);
        loaded := LLVMBuildCall2(builder, fread_string_fnty, fread_string_fn, call_args, 3, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, buf_i8);
        SetPtrArrayElem(call_args, 1, cap);
        loaded := LLVMBuildCall2(builder, read_string_fnty, read_string_fn, call_args, 2, MakeCStr(''));
      END;
    END
    ELSE IF TypeKind(tid) = TK_ENUM THEN
    BEGIN
      { Enumerated values read as a numeric ordinal (manual 13610-13618);
        i32 storage matches the reader's output width. }
      tmp32 := EntryAlloca(i32ty, '');
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, tmp32);
        loaded := LLVMBuildCall2(builder, fread_int_fnty, fread_int_fn, call_args, 2, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(1);
        SetPtrArrayElem(call_args, 0, tmp32);
        loaded := LLVMBuildCall2(builder, read_int_fnty, read_int_fn, call_args, 1, MakeCStr(''));
      END;
      loaded := LLVMBuildLoad2(builder, i32ty, tmp32, MakeCStr(''));
      LLVMBuildStore(builder, loaded, addr);
    END
    ELSE IF TypeKind(tid) = TK_BOOLEAN THEN
    BEGIN
      { Number-or-name BOOLEAN read (manual 13610-13618), file and stdin
        forms alike. }
      tmp32 := EntryAlloca(i32ty, '');
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(4);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, tmp32);
        SetPtrArrayElem(call_args, 2, BoolNameTable);
        SetPtrArrayElem(call_args, 3, LLVMConstInt(i32ty, 2, 0));
        loaded := LLVMBuildCall2(builder, fread_enum_name_fnty, fread_enum_name_fn, call_args, 4, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(3);
        SetPtrArrayElem(call_args, 0, tmp32);
        SetPtrArrayElem(call_args, 1, BoolNameTable);
        SetPtrArrayElem(call_args, 2, LLVMConstInt(i32ty, 2, 0));
        loaded := LLVMBuildCall2(builder, read_enum_name_fnty, read_enum_name_fn, call_args, 3, MakeCStr(''));
      END;
      loaded := LLVMBuildLoad2(builder, i32ty, tmp32, MakeCStr(''));
      loaded := LLVMBuildTrunc(builder, loaded, i1ty, MakeCStr(''));
      LLVMBuildStore(builder, loaded, addr);
    END
    ELSE IF TypeKind(tid) = TK_POINTER THEN
    BEGIN
      { Pointer-as-number read, round-tripping WRITE's unsigned-decimal
        pointer format (manual 13620-13623). }
      tmp64 := EntryAlloca(i64ty, '');
      IF using_file THEN
      BEGIN
        call_args := AllocPtrArray(2);
        SetPtrArrayElem(call_args, 0, fcb_ptr);
        SetPtrArrayElem(call_args, 1, tmp64);
        loaded := LLVMBuildCall2(builder, fread_ptr_fnty, fread_ptr_fn, call_args, 2, MakeCStr(''));
      END
      ELSE
      BEGIN
        call_args := AllocPtrArray(1);
        SetPtrArrayElem(call_args, 0, tmp64);
        loaded := LLVMBuildCall2(builder, read_ptr_fnty, read_ptr_fn, call_args, 1, MakeCStr(''));
      END;
      loaded := LLVMBuildLoad2(builder, i64ty, tmp64, MakeCStr(''));
      loaded := LLVMBuildIntToPtr(builder, loaded, i8ptrty, MakeCStr(''));
      LLVMBuildStore(builder, loaded, addr);
    END
    ELSE
      AbortWith('codegen: unsupported READ argument type');
  END;

  IF is_readln THEN
  BEGIN
    IF using_file THEN
    BEGIN
      call_args := AllocPtrArray(1);
      SetPtrArrayElem(call_args, 0, fcb_ptr);
      loaded := LLVMBuildCall2(builder, freadln_skip_fnty, freadln_skip_fn, call_args, 1, MakeCStr(''));
    END
    ELSE
      loaded := LLVMBuildCall2(builder, readln_skip_fnty, readln_skip_fn, NIL, 0, MakeCStr(''));
  END;
END;

PROCEDURE CodegenReadSet(args: ADRMEM);
{ READSET([file,] dest, set_of_char): manual-documented extended I/O builtin
  (djvu.txt:9047-9081-adjacent), lowered straight to the runtime's existing
  pas_freadset (runtime/fileops.c) -- no runtime changes needed, only this
  call-site wiring, mirroring the reference's builtin_readset. The 2-argument
  form (implicit INPUT) routes through GetDefaultInputFcbPtr, which lazily
  attaches the predeclared INPUT/OUTPUT FCBs (RegisterPredeclaredFiles) to
  real stdin/stdout via pas_file_attach_std -- mirroring the reference's
  own lazy-attach-on-first-use behavior. }
VAR
  nargs, start_idx: INTEGER32;
  arg0, dest_node, set_node: ADRMEM;
  fcb_ptr: ADRMEM;
  symi: INTEGER32;
  addr, buf_i8, cap, set_val, set_slot, gep_idx, words_ptr, call_args, discard: ADRMEM;
  tid: INTEGER;
BEGIN
  nargs := ArrSize(args);
  IF (nargs <> 2) AND (nargs <> 3) THEN
    AbortWith('codegen: READSET expects 2 or 3 arguments');
  IF nargs = 3 THEN
  BEGIN
    arg0 := ArrItem(args, 0);
    fcb_ptr := LoadFileFcbPtr(GetStr(arg0, 'name'));
    start_idx := 1;
  END
  ELSE
  BEGIN
    fcb_ptr := GetDefaultInputFcbPtr;
    start_idx := 0;
  END;

  dest_node := ArrItem(args, start_idx);
  symi := LookupSym(GetStr(dest_node, 'name'));
  IF symi = 0 THEN AbortWith2('codegen: undefined variable: ', GetStr(dest_node, 'name'));
  tid := symbols[symi].tk;
  IF TypeKind(tid) <> TK_LSTRING THEN
    AbortWith('codegen: READSET destination must be LSTRING');
  addr := symbols[symi].llvm_val;
  buf_i8 := LLVMBuildBitCast(builder, addr, i8ptrty, MakeCStr(''));
  cap := LLVMConstInt(i32ty, types[tid].hi, 0);

  set_node := ArrItem(args, start_idx + 1);
  set_val := CodegenExpr(set_node);
  IF TypeKind(last_val_tk) <> TK_SET THEN
    AbortWith('codegen: READSET set argument must be SET OF CHAR');
  set_slot := EntryAlloca(setty, '');
  LLVMBuildStore(builder, set_val, set_slot);
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  words_ptr := LLVMBuildGEP2(builder, setty, set_slot, gep_idx, 2, MakeCStr(''));

  call_args := AllocPtrArray(4);
  SetPtrArrayElem(call_args, 0, fcb_ptr);
  SetPtrArrayElem(call_args, 1, buf_i8);
  SetPtrArrayElem(call_args, 2, cap);
  SetPtrArrayElem(call_args, 3, words_ptr);
  discard := LLVMBuildCall2(builder, freadset_fnty, freadset_fn, call_args, 4, MakeCStr(''));
END;


BEGIN
END.
