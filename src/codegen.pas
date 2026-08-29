{ Native Pascal Code Generator, pascal1981-dialect implementation.

  Goal: full parity with the Python reference code generator
  (src/pascal1981/codegen/). Built up incrementally -- each supported
  construct is real, but the construct set covered so far is a proper
  subset of the reference. Currently covers: PROGRAM-level and routine-local
  scalar VAR declarations (INTEGER/REAL/BOOLEAN/CHAR); TYPE-declared and
  inline ARRAY/RECORD types (single-dimension, non-PACKED, non-SUPER),
  including arrays of records and indexed/field designator reads and
  writes; the full arithmetic/relational/logical expression operator set
  (no implicit cross-type promotion -- mixing INTEGER and REAL in one
  expression is rejected, not silently coerced); assignment; IF/WHILE/
  REPEAT/FOR and compound statements; WRITE/WRITELN of string-literal/
  scalar arguments; and PROCEDURE/FUNCTION declarations with value and VAR
  parameters (VAR-mode ARRAY/RECORD/LSTRING parameters work; value-mode
  aggregate ones are rejected -- pass by VAR instead), including recursion;
  LSTRING(n) variables (declaration, string-literal assignment,
  WRITE/WRITELN, 1-based character indexing s[i]) and POINTER variables
  (^Type, NEW/DISPOSE, dereference p^ as an lvalue and rvalue); STRING(n)
  variables (declaration, exact-length string-literal assignment,
  WRITE/WRITELN, 1-based character indexing s[i], no length prefix); and
  CONCAT(VAR D: LSTRING; CONST S: STRING-or-LSTRING-or-literal), appending
  S onto D via a runtime byte-copy loop (S's length is not always known at
  compile time, unlike a literal assignment's); SET OF lo..hi variables
  (TYPE-declared, over an INTEGER subrange base only), set constructors
  (`[..]`, both single elements and lo..hi ranges, constant or dynamic --
  all lowered as runtime bit-set instructions rather than the Python
  reference's compile-time-constant-folded words, a deliberate behavioral-
  parity-over-IR-shape-parity tradeoff), the set operators +/-/*, =, <>,
  <=, <, >=, > and IN, and set-to-set assignment; and CASE/OTHERWISE over
  an INTEGER selector with single-constant and comma-separated labels
  (lowered as a sequential test-block chain, not a jump table) -- a lo..hi
  label range is rejected, matching the Python reference's own
  not-yet-supported limitation there, not falling short of it; and
  COPYLST(CONST S; VAR D: LSTRING) and COPYSTR(CONST S; VAR D: STRING),
  both of which overwrite D from scratch (unlike CONCAT's append) --
  COPYLST sets D's length byte to length(S), COPYSTR blank-pads the bytes
  beyond length(S) up to D's fixed capacity with 0x20 (STRING has no
  length byte, so every declared byte must hold a real character); and the
  remaining string builtins that call into libpascalrt's runtime the same
  way printf/malloc/free already do (declared as ordinary LLVM externs a
  program built from this file's IR must link libpascalrt.a to satisfy):
  INSERT/DELETE (in-place shift via memmove, since the shifted range can
  overlap itself), POSITN (1-based substring search), SCANEQ/SCANNE
  (scan for the first character equal/not-equal to a given CHAR), and
  ENCODE/DECODE (format/parse an INTEGER as decimal text into/out of an
  LSTRING -- ENCODE's `value:width` argument works via the same WriteArg
  wrapping WRITE's own width:precision arguments use, since ENCODE/DECODE
  share that argument-list grammar; `:precision` parses but is ignored,
  matching the runtime, which has no REAL-formatting path either; DECODE's
  destination is scoped to INTEGER/CHAR, the two byte-widths its own
  manual documents by name); and, on ordinary WRITE/WRITELN arguments
  (StringLiteral/LSTRING/STRING/INTEGER/REAL/CHAR/BOOLEAN alike), a
  `:width` field honored via printf's own `%*` dynamic-width specifier
  (width is an arbitrary expression, evaluated and sign-extended to i32,
  exactly like the Python reference's coerce_printf_int) -- `:precision`
  parses but is ignored everywhere except REAL/REAL32, matching the
  reference's own faithful-1981 default (its width+precision -> %*.*f
  case, width defaulting to 14 and precision to 0 when only one of the
  pair is given; width alone -> %*E; neither -> %14.7E); and WRITE/WRITELN
  of a BOOLEAN argument, printed as the literal string
  "TRUE"/"FALSE" via a runtime icmp+select between two global string
  constants, same as the reference; and the ordinal/math builtins CHR, ORD,
  ODD, SUCC, PRED, ABS, SQR (pure inline IR, no runtime call) and SQRT,
  SIN, COS, LN, EXP, ARCTAN, TRUNC, ROUND, FLOAT (SQRT/SIN/COS/LN/EXP/
  ARCTAN call straight into libm -- declared+called as ordinary LLVM
  externs exactly like malloc/printf are against libc, so a program built
  from this file's IR must link -lm to satisfy them; TRUNC/ROUND produce a
  16-bit INTEGER here rather than the Python reference's 32-bit result,
  consistent with every other native-INTEGER value in this file), plus
  LOWER/UPPER bound resolution for the fixed-bound cases this file's type
  system represents -- TYPE-declared ARRAY (static lo..hi), STRING(n)
  (1..n), and LSTRING(n) (0..n, its declared capacity, not the runtime
  length) -- the dereferenced form UPPER(p^)/LOWER(p^), which the Python
  reference resolves via a dynamic bound header for heap "super arrays",
  is rejected, since this file has neither super arrays nor multi-
  dimension arrays yet. Also covers WORD (16-bit, tid TK_WORD, same LLVM
  i16 as INTEGER but a distinct tag -- WRITE prints it unsigned (%u,
  zero-extended) and a compile-time INTEGER expression may assign into it
  (the vintage "INTEGER constant changes to WORD" rule, simplified here to
  apply to any expression, not just a literal -- a documented, deliberate
  looseness relative to the Python reference's constant-only version) --
  same-width arithmetic/comparisons still use signed instructions,
  matching the reference's own hardcoded sdiv/srem/icmp-signed even for
  WORD) and INTEGER8 (8-bit signed, tid TK_INTEGER8, LLVM i8 -- feature state
  is now resolved but its gates are not applied until the next work unit, so
  INTEGER8 remains temporarily available in both dialects; only a compile-time
  INTEGER *literal* -- bare or unary-MINUS-wrapped -- may assign into an
  INTEGER8 target, truncated to i8, matching the reference's constant-only
  exemption more closely since narrowing isn't something this file wants
  to allow silently for a non-constant value); plus HIBYTE/LOBYTE
  (INTEGER/WORD argument only, returns CHAR, matching the reference's
  "faithful dialect pair" restriction), WRD (any INTEGER/WORD/CHAR/
  BOOLEAN/INTEGER8 argument widens/passes-through to WORD), and BYWORD
  (packs two INTEGER/WORD/CHAR/BOOLEAN byte-ish values into one WORD).
  Also covers the rest of the wide-integer/REAL32 extension family: WORD8
  (8-bit unsigned, tid TK_WORD8, LLVM i8, prints %u) and WRD8 (any
  non-REAL argument narrows/passes-through to WORD8, mirroring WRD);
  INTEGER32/WORD32 (32-bit, tid TK_INTEGER32/TK_WORD32, LLVM i32) and
  INTEGER64/WORD64 (64-bit, tid TK_INTEGER64/TK_WORD64, LLVM i64, printed
  via %lld/%llu); and REAL32 (32-bit float, tid TK_REAL32, LLVM float),
  which widens implicitly into REAL on assignment (fpext) like the
  reference, plus (a documented, deliberate looseness beyond the
  reference, mirroring INTEGER8's own literal exemption) lets a bare REAL
  literal narrow (fptrunc) into a REAL32 target, since this file's
  RealLiteral codegen has no context-type threading to make the literal
  itself REAL32-typed the way the reference's typechecker does. As with
  WORD/INTEGER8, a compile-time INTEGER *literal* may additionally assign
  into any of these wider integer targets (rebuilt at the target's own
  width, not truncated through the native 16-bit INTEGER path) and adapts
  the same way as an operand in a same-kind BinOp comparison/arithmetic
  expression against another wide-integer-typed operand -- e.g. `w32 > 0`
  -- mirroring the reference's literal_context threading; two operands of
  genuinely different wide-integer/REAL32 widths together (no literal
  involved) are still rejected, same as the file's existing no-implicit-
  promotion rule for plain INTEGER/REAL. Not yet covered: files,
  multi-dimension arrays, CHAR-keyed CASE, CASE label ranges,
  MATHCK/RANGECK-style runtime traps (including CONCAT/COPYLST/COPYSTR/
  INSERT's own capacity overflow,
  which is unchecked -- same simplification as an unchecked array index
  elsewhere in this file), C-ABI externs, units, and DEVICE MODULE/PTX
  generation. Anything not yet covered is
  rejected loudly via AbortWith rather than silently mishandled
  or miscompiled -- reject unhandled constructs instead of guessing, the
  same discipline the earlier native stages (lexer.pas/parser.pas/
  typechecker.pas) already follow.

  Reads the annotated JSON AST produced by pascal1981-typecheck on standard
  input, builds an LLVM module via the LLVM-C API (linked against
  libLLVM), and prints the resulting IR to standard output. On any
  unsupported construct, prints a diagnostic and exits 1 without emitting
  IR, matching the other native stages' error convention. }

(*$INCLUDE:'argparse.inc'*)
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
(*$INCLUDE:'cg_expr.inc'*)
(*$INCLUDE:'cg_io.inc'*)
(*$INCLUDE:'cg_stmt.inc'*)
(*$INCLUDE:'cg_decl.inc'*)
PROGRAM pascal1981_codegen(input, output);

USES argparse, features, jsonutil, cg_base, cg_util, cg_types, cg_symbols, cg_expr_shape, cg_expr_sets, cg_expr_support, cg_expr_literals, cg_expr, cg_io, cg_stmt, cg_decl;

{ ============================== driver =================================== }

VAR
  root, block, body: ADRMEM;
  param_arr: ADRMEM;
  ret_val: ADRMEM;
  verify_msg_raw: ADRMEM;
  verify_msg: PAdr;
  ok: CINT;
  ir_text: ADRMEM;
  res_c: CINT;
  local_ifaces: ADRMEM;
  n_local_ifaces, li: INTEGER32;
  root_nt: Str255;
  is_device_root, is_program, is_implementation, saved_device: BOOLEAN;
  unit_decls, init_body: ADRMEM;
  init_fnty, init_fn, init_bb: ADRMEM;
  init_name, unit_name, device_triple: Str255;
  device_triple_raw, emit_ptx_raw, ptx_cpu_raw, backend_raw: ADRMEM;
  target_out_raw, target_err_out_raw, ptx_err_out_raw, ptx_buffer_out_raw: ADRMEM;
  target_out, target_err_out, ptx_err_out, ptx_buffer_out: PAdr;
  target_ref, target_machine, target_layout, ptx_buffer, ptx_cpu: ADRMEM;
  emit_ptx: BOOLEAN;
  unit_name_len, unit_name_i: INTEGER;
  dialect_arg, arg_error: ArgStr;
  resolved_features: FeatureSet;

PROCEDURE PrintArgError;
VAR
  msg: Str255;
  i, n: INTEGER32;
BEGIN
  ArgError(arg_error);
  n := ORD(arg_error[0]);
  msg[0] := CHR(RETYPE(INTEGER, n));
  i := 1;
  WHILE i <= n DO
  BEGIN
    msg[i] := arg_error[i];
    i := i + 1;
  END;
  EPrint(msg);
END;

PROCEDURE ParseArgs;
BEGIN
  ArgBegin('codegen', 'Pascal-1981 code generator stage.');
  ArgString('dialect', ARG_NO_SHORT, 'vintage',
            'Language dialect: vintage or extended.');
  IF NOT ArgParse THEN
  BEGIN
    IF ArgHelpWanted THEN exit(0);
    PrintArgError;
    exit(1);
  END;
  IF ArgPosCount <> 0 THEN
  BEGIN
    EPrint('error: codegen accepts input only on standard input');
    exit(1);
  END;
  ArgGetStr('dialect', dialect_arg);
  IF (dialect_arg <> 'vintage') AND (dialect_arg <> 'extended') THEN
  BEGIN
    EPrint('error: invalid dialect; expected ''vintage'' or ''extended''');
    exit(1);
  END;
END;

BEGIN
  ParseArgs;
  IF dialect_arg = 'extended' THEN
    ResolveFeatures(DIALECT_EXTENDED, resolved_features)
  ELSE
    ResolveFeatures(DIALECT_VINTAGE, resolved_features);
  CgInitFeatures(resolved_features);
  expr_depth := 0;
  stmt_depth := 0;
  root := ReadAllStdin;
  root_nt := NodeType(root);
  is_device_root := GetBool(root, 'is_device');
  is_device_compiland := is_device_root;
  is_nvptx_device := FALSE;
  lowering_spliced_interface := FALSE;
  defining_implementation := root_nt = 'ImplementationUnit';
  device_triple_raw := NIL;
  emit_ptx_raw := getenv(MakeCStr('PASCAL_EMIT_PTX'));
  emit_ptx := emit_ptx_raw <> NIL;
  noalias_kernel_params := getenv(MakeCStr('PASCAL_NOALIAS_KERNEL_PARAMS')) <> NIL;
  device_backend_cuda := FALSE;
  backend_raw := getenv(MakeCStr('PASCAL_DEVICE_BACKEND'));
  IF backend_raw <> NIL THEN
    device_backend_cuda := CStrToStr255(backend_raw) = 'cuda';
  IF is_device_compiland THEN
  BEGIN
    device_triple_raw := getenv(MakeCStr('PASCAL_DEVICE_TRIPLE'));
    IF device_triple_raw <> NIL THEN
    BEGIN
      device_triple := CStrToStr255(device_triple_raw);
      is_nvptx_device := device_triple = 'nvptx64-nvidia-cuda';
    END;
  END;

  is_program := root_nt = 'ProgramUnit';
  is_implementation := root_nt = 'ImplementationUnit';
  IF (NOT is_program) AND (root_nt <> 'ModuleUnit') AND
     (root_nt <> 'InterfaceUnit') AND (NOT is_implementation) THEN
    AbortWith2('codegen: unsupported root unit kind: ', root_nt);

  ctx := LLVMContextCreate;
  modl := LLVMModuleCreateWithNameInContext(MakeCStr('pascal_program'), ctx);
  IF is_nvptx_device THEN LLVMSetTarget(modl, device_triple_raw)
  ELSE
  BEGIN
    { These must stay synchronized with TypeSizeBytes/TypeAlignBytes's
      x86-64 SysV layout assumptions.

      Stating the triple rather than leaving the module untargeted (which
      let clang substitute the host's) makes an assumption this stage
      already had explicit: SysVAggClass, the byval/sret classification and
      the size/align tables are all x86-64 SysV, so IR produced here was
      never host-portable -- it merely used to be mislabelled on a non-x86-64
      host. On such a host clang now warns and overrides instead of silently
      compiling x86-64-classified IR under another layout. README scopes the
      toolchain to Ubuntu x86_64; a second target needs those tables
      parameterised, not just this string. }
    LLVMSetTarget(modl, MakeCStr('x86_64-pc-linux-gnu'));
    LLVMSetDataLayout(modl, MakeCStr('e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128'));
  END;
  IF emit_ptx AND (NOT is_nvptx_device) THEN
    AbortWith('codegen: PASCAL_EMIT_PTX requires a DEVICE compiland with PASCAL_DEVICE_TRIPLE=nvptx64-nvidia-cuda');
  i32ty := LLVMInt32TypeInContext(ctx);
  i16ty := LLVMInt16TypeInContext(ctx);
  i8ty := LLVMInt8TypeInContext(ctx);
  i1ty := LLVMInt1TypeInContext(ctx);
  i64ty := LLVMInt64TypeInContext(ctx);
  dblty := LLVMDoubleTypeInContext(ctx);
  f32ty := LLVMFloatTypeInContext(ctx);
  i8ptrty := LLVMPointerType(i8ty, 0);
  voidty := LLVMVoidTypeInContext(ctx);
  setty := LLVMArrayType(i64ty, 4);
  generic_set_tid := 0;
  param_arr := AllocPtrArray(10);
  SetPtrArrayElem(param_arr, 0, i32ty);
  SetPtrArrayElem(param_arr, 1, i32ty);
  SetPtrArrayElem(param_arr, 2, i32ty);
  SetPtrArrayElem(param_arr, 3, i32ty);
  SetPtrArrayElem(param_arr, 4, i8ptrty);
  SetPtrArrayElem(param_arr, 5, i8ptrty);
  SetPtrArrayElem(param_arr, 6, i8ptrty);
  SetPtrArrayElem(param_arr, 7, i32ty);
  SetPtrArrayElem(param_arr, 8, i8ty);
  SetPtrArrayElem(param_arr, 9, i32ty);
  filefcbty := LLVMStructTypeInContext(ctx, param_arr, 10, 0);

  { A UNIT compiland (ImplementationUnit) is a library object, not a program
    -- no main/entry block, matching the reference's is_root_compiland check
    (only PROGRAM owns the process-wide main/@input/@output). builder still
    needs to exist since CodegenRoutineDecl repositions it per routine
    regardless of compiland kind. }
  IF is_program THEN
  BEGIN
    { main always takes (argc, argv) so program-heading parameters can be
      bound from the command line (manual 13-5..13-7) -- an ordinary
      program that ignores them is unaffected, matching the reference's own
      main(int, char**) (link-compatible with a plain main(void) caller). }
    param_arr := AllocPtrArray(2);
    SetPtrArrayElem(param_arr, 0, i32ty);
    SetPtrArrayElem(param_arr, 1, LLVMPointerType(i8ptrty, 0));
    main_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
    main_fn := LLVMAddFunction(modl, MakeCStr('main'), main_fnty);
    main_argc_val := LLVMGetParam(main_fn, 0);
    main_argv_val := LLVMGetParam(main_fn, 1);
    entry_bb := LLVMAppendBasicBlockInContext(ctx, main_fn, MakeCStr('entry'));
    builder := LLVMCreateBuilderInContext(ctx);
    LLVMPositionBuilderAtEnd(builder, entry_bb);
    cur_fn := main_fn;
  END
  ELSE
    builder := LLVMCreateBuilderInContext(ctx);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  printf_fnty := LLVMFunctionType(i32ty, param_arr, 1, 1);
  printf_fn := LLVMAddFunction(modl, MakeCStr('printf'), printf_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_reset_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_reset_fn := LLVMAddFunction(modl, MakeCStr('pas_file_reset'), file_reset_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_rewrite_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_rewrite_fn := LLVMAddFunction(modl, MakeCStr('pas_file_rewrite'), file_rewrite_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_get_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_get_fn := LLVMAddFunction(modl, MakeCStr('pas_file_get'), file_get_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_put_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_put_fn := LLVMAddFunction(modl, MakeCStr('pas_file_put'), file_put_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_close_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_close_fn := LLVMAddFunction(modl, MakeCStr('pas_file_close'), file_close_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_discard_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_discard_fn := LLVMAddFunction(modl, MakeCStr('pas_file_discard'), file_discard_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i32ty);
  file_assign_fnty := LLVMFunctionType(voidty, param_arr, 3, 0);
  file_assign_fn := LLVMAddFunction(modl, MakeCStr('pas_file_assign'), file_assign_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_eof_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  file_eof_fn := LLVMAddFunction(modl, MakeCStr('pas_file_eof'), file_eof_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_eoln_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  file_eoln_fn := LLVMAddFunction(modl, MakeCStr('pas_file_eoln'), file_eoln_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_buffer_fnty := LLVMFunctionType(i8ptrty, param_arr, 1, 0);
  file_buffer_fn := LLVMAddFunction(modl, MakeCStr('pas_file_buffer'), file_buffer_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  file_touch_buffer_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  file_touch_buffer_fn := LLVMAddFunction(modl, MakeCStr('pas_file_touch_buffer'), file_touch_buffer_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, i32ty);
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i8ptrty, 0));
  args_init_fnty := LLVMFunctionType(voidty, param_arr, 2, 0);
  args_init_fn := LLVMAddFunction(modl, MakeCStr('pas_args_init'), args_init_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, i32ty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  arg_begin_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  arg_begin_fn := LLVMAddFunction(modl, MakeCStr('pas_arg_begin'), arg_begin_fnty);

  arg_end_fnty := LLVMFunctionType(voidty, NIL, 0, 0);
  arg_end_fn := LLVMAddFunction(modl, MakeCStr('pas_arg_end'), arg_end_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  write_fmt_fnty := LLVMFunctionType(i32ty, param_arr, 2, 1);
  write_fmt_fn := LLVMAddFunction(modl, MakeCStr('pas_write_fmt'), write_fmt_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i32ty, 0));
  fread_int_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  fread_int_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_int'), fread_int_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i16ty, 0));
  fread_word_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  fread_word_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_word'), fread_word_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i64ty, 0));
  fread_ptr_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  fread_ptr_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_ptr'), fread_ptr_fnty);

  param_arr := AllocPtrArray(4);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i32ty, 0));
  SetPtrArrayElem(param_arr, 2, LLVMPointerType(i8ptrty, 0));
  SetPtrArrayElem(param_arr, 3, i32ty);
  fread_enum_name_fnty := LLVMFunctionType(i32ty, param_arr, 4, 0);
  fread_enum_name_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_enum_name'), fread_enum_name_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(dblty, 0));
  fread_real_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  fread_real_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_real'), fread_real_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i8ty, 0));
  fread_char_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  fread_char_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_char'), fread_char_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i32ty);
  fread_lstring_fnty := LLVMFunctionType(i32ty, param_arr, 3, 0);
  fread_lstring_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_lstring'), fread_lstring_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i32ty);
  fread_string_fnty := LLVMFunctionType(i32ty, param_arr, 3, 0);
  fread_string_fn := LLVMAddFunction(modl, MakeCStr('pas_fread_string'), fread_string_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  freadln_skip_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  freadln_skip_fn := LLVMAddFunction(modl, MakeCStr('pas_freadln_skip'), freadln_skip_fnty);

  param_arr := AllocPtrArray(4);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i32ty);
  SetPtrArrayElem(param_arr, 3, LLVMPointerType(i64ty, 0));
  freadset_fnty := LLVMFunctionType(voidty, param_arr, 4, 0);
  freadset_fn := LLVMAddFunction(modl, MakeCStr('pas_freadset'), freadset_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(filefcbty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(filefcbty, 0));
  file_attach_std_fnty := LLVMFunctionType(voidty, param_arr, 2, 0);
  file_attach_std_fn := LLVMAddFunction(modl, MakeCStr('pas_file_attach_std'), file_attach_std_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(i32ty, 0));
  read_int_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  read_int_fn := LLVMAddFunction(modl, MakeCStr('pas_read_int'), read_int_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(i16ty, 0));
  read_word_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  read_word_fn := LLVMAddFunction(modl, MakeCStr('pas_read_word'), read_word_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(i64ty, 0));
  read_ptr_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  read_ptr_fn := LLVMAddFunction(modl, MakeCStr('pas_read_ptr'), read_ptr_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(i32ty, 0));
  SetPtrArrayElem(param_arr, 1, LLVMPointerType(i8ptrty, 0));
  SetPtrArrayElem(param_arr, 2, i32ty);
  read_enum_name_fnty := LLVMFunctionType(i32ty, param_arr, 3, 0);
  read_enum_name_fn := LLVMAddFunction(modl, MakeCStr('pas_read_enum_name'), read_enum_name_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(dblty, 0));
  read_real_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  read_real_fn := LLVMAddFunction(modl, MakeCStr('pas_read_real'), read_real_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, LLVMPointerType(i8ty, 0));
  read_char_fnty := LLVMFunctionType(i32ty, param_arr, 1, 0);
  read_char_fn := LLVMAddFunction(modl, MakeCStr('pas_read_char'), read_char_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i32ty);
  read_lstring_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  read_lstring_fn := LLVMAddFunction(modl, MakeCStr('pas_read_lstring'), read_lstring_fnty);

  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i32ty);
  read_string_fnty := LLVMFunctionType(i32ty, param_arr, 2, 0);
  read_string_fn := LLVMAddFunction(modl, MakeCStr('pas_read_string'), read_string_fnty);

  readln_skip_fnty := LLVMFunctionType(voidty, NIL, 0, 0);
  readln_skip_fn := LLVMAddFunction(modl, MakeCStr('pas_readln_skip'), readln_skip_fnty);

  param_arr := AllocPtrArray(1);
  { C malloc takes size_t; the supported native host ABI is LP64. }
  SetPtrArrayElem(param_arr, 0, i64ty);
  malloc_fnty := LLVMFunctionType(i8ptrty, param_arr, 1, 0);
  malloc_fn := LLVMAddFunction(modl, MakeCStr('malloc'), malloc_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  free_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  free_fn := LLVMAddFunction(modl, MakeCStr('free'), free_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i64ty);
  memmove_fnty := LLVMFunctionType(i8ptrty, param_arr, 3, 0);
  memmove_fn := LLVMAddFunction(modl, MakeCStr('memmove'), memmove_fnty);

  param_arr := AllocPtrArray(8);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i64ty);
  SetPtrArrayElem(param_arr, 2, i64ty);
  SetPtrArrayElem(param_arr, 3, i64ty);
  SetPtrArrayElem(param_arr, 4, i64ty);
  SetPtrArrayElem(param_arr, 5, i64ty);
  SetPtrArrayElem(param_arr, 6, i64ty);
  SetPtrArrayElem(param_arr, 7, LLVMPointerType(i8ptrty, 0));
  { entry plus six geometry values plus argv: the CPU and CUDA shims share
    this eight-parameter launch ABI. }
  launch_fnty := LLVMFunctionType(voidty, param_arr, 8, 0);
  launch_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_launch'), launch_fnty);

  { The two module-resolution steps ahead of it: cuModuleLoadData(registry,
    ptx) and cuModuleGetFunction(module, name), both shaped as i8*(i8*, i8*).
    The CPU and CUDA shims implement the same three-call path. }
  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  module_load_fnty := LLVMFunctionType(i8ptrty, param_arr, 2, 0);
  module_load_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_module_load'), module_load_fnty);
  param_arr := AllocPtrArray(2);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  module_getfn_fnty := LLVMFunctionType(i8ptrty, param_arr, 2, 0);
  module_getfn_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_module_get_function'), module_getfn_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, i64ty);
  dev_alloc_fnty := LLVMFunctionType(i8ptrty, param_arr, 1, 0);
  dev_alloc_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_alloc'), dev_alloc_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i64ty);
  dev_copy_to_fnty := LLVMFunctionType(voidty, param_arr, 3, 0);
  dev_copy_to_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_copy_to'), dev_copy_to_fnty);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i64ty);
  dev_copy_from_fnty := LLVMFunctionType(voidty, param_arr, 3, 0);
  dev_copy_from_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_copy_from'), dev_copy_from_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  dev_free_fnty := LLVMFunctionType(voidty, param_arr, 1, 0);
  dev_free_fn := LLVMAddFunction(modl, MakeCStr('pas_dev_free'), dev_free_fnty);

  byval_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('byval'), 5);
  sret_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('sret'), 4);
  align_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('align'), 5);
  readonly_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('readonly'), 8);
  nocapture_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('nocapture'), 9);
  captures_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('captures'), 8);
  noalias_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('noalias'), 7);
  deref_kind_id := LLVMGetEnumAttributeKindForName(MakeCStr('dereferenceable'), 15);

  param_arr := AllocPtrArray(3);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i8ptrty);
  SetPtrArrayElem(param_arr, 2, i64ty);
  memcmp_fnty := LLVMFunctionType(i32ty, param_arr, 3, 0);
  memcmp_fn := LLVMAddFunction(modl, MakeCStr('memcmp'), memcmp_fnty);

  param_arr := AllocPtrArray(4);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i32ty);
  SetPtrArrayElem(param_arr, 2, i8ptrty);
  SetPtrArrayElem(param_arr, 3, i32ty);
  positn_fnty := LLVMFunctionType(i32ty, param_arr, 4, 0);
  positn_fn := LLVMAddFunction(modl, MakeCStr('positn'), positn_fnty);

  param_arr := AllocPtrArray(6);
  SetPtrArrayElem(param_arr, 0, i32ty);
  SetPtrArrayElem(param_arr, 1, i8ty);
  SetPtrArrayElem(param_arr, 2, i8ptrty);
  SetPtrArrayElem(param_arr, 3, i32ty);
  SetPtrArrayElem(param_arr, 4, i32ty);
  SetPtrArrayElem(param_arr, 5, i32ty);
  scaneq_fnty := LLVMFunctionType(i32ty, param_arr, 6, 0);
  scaneq_fn := LLVMAddFunction(modl, MakeCStr('scaneq'), scaneq_fnty);

  param_arr := AllocPtrArray(6);
  SetPtrArrayElem(param_arr, 0, i32ty);
  SetPtrArrayElem(param_arr, 1, i8ty);
  SetPtrArrayElem(param_arr, 2, i8ptrty);
  SetPtrArrayElem(param_arr, 3, i32ty);
  SetPtrArrayElem(param_arr, 4, i32ty);
  SetPtrArrayElem(param_arr, 5, i32ty);
  scanne_fnty := LLVMFunctionType(i32ty, param_arr, 6, 0);
  scanne_fn := LLVMAddFunction(modl, MakeCStr('scanne'), scanne_fnty);

  param_arr := AllocPtrArray(7);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i32ty);
  SetPtrArrayElem(param_arr, 2, i8ptrty);
  SetPtrArrayElem(param_arr, 3, i32ty);
  SetPtrArrayElem(param_arr, 4, i32ty);
  SetPtrArrayElem(param_arr, 5, i32ty);
  SetPtrArrayElem(param_arr, 6, i32ty);
  encode_fnty := LLVMFunctionType(i32ty, param_arr, 7, 0);
  encode_fn := LLVMAddFunction(modl, MakeCStr('encode_value'), encode_fnty);

  param_arr := AllocPtrArray(7);
  SetPtrArrayElem(param_arr, 0, i8ptrty);
  SetPtrArrayElem(param_arr, 1, i32ty);
  SetPtrArrayElem(param_arr, 2, i8ptrty);
  SetPtrArrayElem(param_arr, 3, i32ty);
  SetPtrArrayElem(param_arr, 4, i32ty);
  SetPtrArrayElem(param_arr, 5, i32ty);
  SetPtrArrayElem(param_arr, 6, i32ty);
  decode_fnty := LLVMFunctionType(i32ty, param_arr, 7, 0);
  decode_fn := LLVMAddFunction(modl, MakeCStr('decode_value'), decode_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, dblty);
  sqrt_fnty := LLVMFunctionType(dblty, param_arr, 1, 0);
  sqrt_fn := LLVMAddFunction(modl, MakeCStr('sqrt'), sqrt_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, dblty);
  sin_fnty := LLVMFunctionType(dblty, param_arr, 1, 0);
  sin_fn := LLVMAddFunction(modl, MakeCStr('sin'), sin_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, dblty);
  cos_fnty := LLVMFunctionType(dblty, param_arr, 1, 0);
  cos_fn := LLVMAddFunction(modl, MakeCStr('cos'), cos_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, dblty);
  log_fnty := LLVMFunctionType(dblty, param_arr, 1, 0);
  log_fn := LLVMAddFunction(modl, MakeCStr('log'), log_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, dblty);
  exp_fnty := LLVMFunctionType(dblty, param_arr, 1, 0);
  exp_fn := LLVMAddFunction(modl, MakeCStr('exp'), exp_fnty);

  param_arr := AllocPtrArray(1);
  SetPtrArrayElem(param_arr, 0, dblty);
  atan_fnty := LLVMFunctionType(dblty, param_arr, 1, 0);
  atan_fn := LLVMAddFunction(modl, MakeCStr('atan'), atan_fnty);

  nsymbols := 0;
  scope_top := 0;
  in_local_scope := FALSE;
  nroutines := 0;
  nconsts := 0;
  cur_func_name := '';
  loop_depth := 0;
  nlabels := 0;
  cur_routine_has_labels := FALSE;
  pending_loop_label := '';
  ntypes := 13; { ids 1..13 are the bare TK_INTEGER..TK_ADRMEM scalars, not
                 `types` table entries -- the first RegisterType call must
                 hand out id 14, not 1. }
  nfields := 0;
  dev_ro_count := 0;
  nkernels := 0;
  klaunch_registry_gv := NIL;
  device_ptx_gv := NIL;

  { local_interfaces: InterfaceUnit blocks spliced in ahead of the PROGRAM
    keyword via $INCLUDE (e.g. jsonutil.inc's "INTERFACE; UNIT jsonutil(...)
    ... END;"), holding declarations -- notably the Str255 = LSTRING(255)
    TYPE alias -- that ordinary top-level code in this same file (and its
    own EXTERN routine signatures, spliced in right alongside) depends on.
    Not part of block.decls at all, so must be walked separately, before
    the real program block, to match declaration order in the source. }
  local_ifaces := GetObj(root, 'local_interfaces');
  IF local_ifaces <> NIL THEN
  BEGIN
    n_local_ifaces := ArrSize(local_ifaces);
    FOR li := 0 TO n_local_ifaces - 1 DO
    BEGIN
      { A DEVICE INTERFACE spliced into a host compiland (the shape a host
        PROGRAM gets from `USES vadd (add)`) must be lowered in *device*
        context, or an ADS(GLOBAL) OF T parameter would be rejected outright
        here while the separately compiled kernel takes an address-space
        pointer. The device triple only ever comes from a DEVICE root, so a
        host compiland lowers these against the CPU device: every ADS space
        collapses to address space zero, which is exactly the flat pointer
        the CPU shim's kernel definition expects. }
      saved_device := is_device_compiland;
      is_device_compiland := is_device_compiland OR
        GetBool(ArrItem(local_ifaces, li), 'is_device');
      lowering_spliced_interface := TRUE;
      CodegenDeclList(GetObj(ArrItem(local_ifaces, li), 'decls'));
      lowering_spliced_interface := FALSE;
      is_device_compiland := saved_device;
    END;
  END;
  CheckUsesClauses(root, local_ifaces);

  IF is_program THEN
  BEGIN
    block := GetObj(root, 'block');
    IF NodeType(block) <> 'Block' THEN
      AbortWith('codegen: expected Block under ProgramUnit');

    CodegenDeclList(GetObj(block, 'decls'));
    IF NOT is_device_compiland THEN RegisterPredeclaredFiles;
    EmitUnitInitCalls;
    CodegenProgramParameters(root);

    body := GetObj(block, 'body');
    SetupFunctionLabels(body);
    CodegenStmtArray(body);

    EmitLaunchRegistry;
    ret_val := LLVMBuildRet(builder, LLVMConstInt(i32ty, 0, 0));
  END
  ELSE
  BEGIN
    { MODULE and INTERFACE compilands are library objects with root-level
      declarations. An IMPLEMENTATION's matching interface was already
      walked from local_interfaces above, so its declarations reconcile with
      those forward placeholders instead of registering duplicates. }
    unit_decls := GetObj(root, 'decls');
    { The kernel-entry readonly summary needs every locally defined device
      routine registered before the first body is lowered -- an entry may call
      a helper declared later in the source. }
    IF is_nvptx_device THEN RegisterDevRoutines(unit_decls);
    CodegenDeclList(unit_decls);

    { Every ordinary IMPLEMENTATION *and* MODULE compiland now emits its
      pascal_init_<name> unconditionally, with an empty (just `RETURN 0`)
      body when it has no init_body of its own (a MODULE has no init syntax
      at all, so its own emitted body is always empty) -- EmitUnitInitCalls
      (see the is_program branch above) calls every USES'd unit's init
      unconditionally too, without knowing from the importer's side alone
      whether the exporting compiland was spelled MODULE or IMPLEMENTATION
      OF, so the target has to always exist as a real symbol to link
      against either way. DEVICE units have no host startup context at
      all: reject an initializer rather than emitting a host function into
      a device object, and skip emitting pascal_init_ for them entirely,
      since nothing ever calls a device unit's init this way. }
    init_body := GetObj(root, 'init_body');
    IF is_implementation AND is_device_root AND
       (init_body <> NIL) AND (ArrSize(init_body) > 0) THEN
      AbortWith('codegen: DEVICE IMPLEMENTATION units cannot have initialization bodies');
    IF (is_implementation OR (root_nt = 'ModuleUnit')) AND NOT is_device_root THEN
    BEGIN
      init_name := 'pascal_init_';
      unit_name := GetStr(root, 'name');
      { LLVM symbol spelling is case-sensitive; use the same lower-case
        unit suffix as the reference so separately built objects agree. }
      unit_name_len := ORD(unit_name[0]);
      FOR unit_name_i := 1 TO unit_name_len DO
        IF (unit_name[unit_name_i] >= 'A') AND (unit_name[unit_name_i] <= 'Z') THEN
          unit_name[unit_name_i] := CHR(ORD(unit_name[unit_name_i]) + 32);
      CONCAT(init_name, unit_name);
      init_fnty := LLVMFunctionType(i32ty, NIL, 0, 0);
      init_fn := LLVMAddFunction(modl, MakeCStr(init_name), init_fnty);
      init_bb := LLVMAppendBasicBlockInContext(ctx, init_fn, MakeCStr('entry'));
      LLVMPositionBuilderAtEnd(builder, init_bb);
      cur_fn := init_fn;
      cur_func_name := '';
      IF (init_body <> NIL) AND (ArrSize(init_body) > 0) THEN
      BEGIN
        SetupFunctionLabels(init_body);
        CodegenStmtArray(init_body);
      END;
      IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
        ret_val := LLVMBuildRet(builder, LLVMConstInt(i32ty, 0, 0));
    END;
  END;

  verify_msg_raw := malloc(8);
  verify_msg := verify_msg_raw;
  verify_msg^ := NIL;
  { LLVMVerifyModule is a necessary gate, not a sufficient one: it catches
    malformed IR (type errors, malformed instructions, dominance violations)
    but not miscompilation. A module can verify clean and still produce wrong
    output -- the by-value-aggregate ABI mismatch and the EXTERN uniquification
    bug (malloc.1/free.2, where a second LLVMAddFunction silently uniquified
    to a symbol nothing links against) were both verifier-clean but wrong, and
    each was found only by clang-linking the output and running it. Any new
    codegen path must be validated by linking the emitted IR against
    libpascalrt.a and running it on real input, not by verification alone;
    tests/test_native_parity.py::TestNativeLinkAndRun is the runtime gate that
    enforces this for the self-hosting codegen paths. }
  ok := LLVMVerifyModule(modl, LLVMAbortProcessAction, verify_msg_raw);
  IF ok <> 0 THEN
  BEGIN
    EPrint('codegen: module verification failed:');
    EPrintC(verify_msg^);
    exit(1);
  END;

  IF emit_ptx THEN
  BEGIN
    { This is deliberately a target-machine emission mode, not a shell-out to
      llc: the native compiler owns the complete LLVM path just like the
      Python driver. LLVMAssemblyFile is enum value 0. }
    LLVMInitializeNVPTXTargetInfo;
    LLVMInitializeNVPTXTarget;
    LLVMInitializeNVPTXTargetMC;
    LLVMInitializeNVPTXAsmPrinter;
    target_out_raw := malloc(8);
    target_err_out_raw := malloc(8);
    target_out := target_out_raw;
    target_err_out := target_err_out_raw;
    target_out^ := NIL;
    target_err_out^ := NIL;
    ok := LLVMGetTargetFromTriple(device_triple_raw, target_out_raw, target_err_out_raw);
    IF ok <> 0 THEN
    BEGIN
      EPrint('codegen: cannot select NVPTX target:');
      EPrintC(target_err_out^);
      exit(1);
    END;
    target_ref := target_out^;
    ptx_cpu_raw := getenv(MakeCStr('PASCAL_PTX_CPU'));
    IF ptx_cpu_raw = NIL THEN ptx_cpu := MakeCStr('sm_70')
    ELSE ptx_cpu := ptx_cpu_raw;
    { LLVMCodeGenLevelNone, LLVMRelocDefault, LLVMCodeModelDefault. }
    target_machine := LLVMCreateTargetMachine(target_ref, device_triple_raw, ptx_cpu, MakeCStr(''), 0, 0, 0);
    IF target_machine = NIL THEN AbortWith('codegen: failed to create NVPTX target machine');
    target_layout := LLVMCreateTargetDataLayout(target_machine);
    LLVMSetModuleDataLayout(modl, target_layout);
    ptx_err_out_raw := malloc(8);
    ptx_buffer_out_raw := malloc(8);
    ptx_err_out := ptx_err_out_raw;
    ptx_buffer_out := ptx_buffer_out_raw;
    ptx_err_out^ := NIL;
    ptx_buffer_out^ := NIL;
    ok := LLVMTargetMachineEmitToMemoryBuffer(target_machine, modl, 0, ptx_err_out_raw, ptx_buffer_out_raw);
    IF ok <> 0 THEN
    BEGIN
      EPrint('codegen: NVPTX assembly emission failed:');
      EPrintC(ptx_err_out^);
      exit(1);
    END;
    ptx_buffer := ptx_buffer_out^;
    res_c := puts(LLVMGetBufferStart(ptx_buffer));
    LLVMDisposeMemoryBuffer(ptx_buffer);
    LLVMDisposeTargetMachine(target_machine);
  END
  ELSE
  BEGIN
    ir_text := LLVMPrintModuleToString(modl);
    res_c := puts(ir_text);
  END;
END.
