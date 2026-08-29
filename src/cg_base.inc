{ Shared declarations and compiler state for separately compiled codegen units. }

INTERFACE;
UNIT cg_base;
USES jsonutil;

FUNCTION LLVMContextCreate: ADRMEM [C];
FUNCTION LLVMModuleCreateWithNameInContext(id: ADRMEM; ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMInt32TypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMInt16TypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMInt8TypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMInt1TypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMInt64TypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMDoubleTypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMIntTypeInContext(ctx: ADRMEM; nbits: CINT): ADRMEM [C];
FUNCTION LLVMPointerType(elem_ty: ADRMEM; addr_space: CINT): ADRMEM [C];
FUNCTION LLVMArrayType(elem_ty: ADRMEM; count: CINT): ADRMEM [C];
FUNCTION LLVMVectorType(elem_ty: ADRMEM; count: CINT): ADRMEM [C];
FUNCTION LLVMStructTypeInContext(ctx: ADRMEM; elem_tys: ADRMEM; count: CINT; is_packed: CINT): ADRMEM [C];
FUNCTION LLVMConstNull(ty: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildGEP2(b: ADRMEM; ty: ADRMEM; ptr: ADRMEM; indices: ADRMEM; nindices: CINT; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildBitCast(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildPtrToInt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildIntToPtr(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildZExt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildTrunc(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMFunctionType(ret_ty: ADRMEM; params: ADRMEM; pcount: CINT; vararg: CINT): ADRMEM [C];
FUNCTION LLVMAddFunction(m: ADRMEM; name: ADRMEM; fty: ADRMEM): ADRMEM [C];
FUNCTION LLVMGetNamedFunction(m: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMAppendBasicBlockInContext(ctx: ADRMEM; fn: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMCreateBuilderInContext(ctx: ADRMEM): ADRMEM [C];
PROCEDURE LLVMPositionBuilderAtEnd(b: ADRMEM; bb: ADRMEM) [C];
PROCEDURE LLVMSetTarget(m: ADRMEM; triple: ADRMEM) [C];
PROCEDURE LLVMSetDataLayout(m: ADRMEM; layout: ADRMEM) [C];
PROCEDURE LLVMSetFunctionCallConv(fn: ADRMEM; cc: CINT) [C];
FUNCTION LLVMMDStringInContext2(ctx: ADRMEM; str: ADRMEM; slen: CLONG): ADRMEM [C];
FUNCTION LLVMMDNodeInContext2(ctx: ADRMEM; mds: ADRMEM; nmds: CLONG): ADRMEM [C];
FUNCTION LLVMValueAsMetadata(v: ADRMEM): ADRMEM [C];
FUNCTION LLVMMetadataAsValue(ctx: ADRMEM; md: ADRMEM): ADRMEM [C];
PROCEDURE LLVMAddNamedMetadataOperand(m: ADRMEM; name: ADRMEM; v: ADRMEM) [C];
FUNCTION LLVMGetMDKindIDInContext(ctx: ADRMEM; name: ADRMEM; n: CINT): CINT [C];
PROCEDURE LLVMSetMetadata(v: ADRMEM; kind: CINT; md: ADRMEM) [C];
PROCEDURE LLVMReplaceMDNodeOperandWith(v: ADRMEM; idx: CINT; replacement: ADRMEM) [C];
FUNCTION LLVMBuildGlobalStringPtr(b: ADRMEM; str: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMConstInt(ty: ADRMEM; n: CLONG; signext: CINT): ADRMEM [C];

{ Truncation toward zero into 64 bits, in the runtime because Pascal's TRUNC
  cannot do it: TRUNC lowers to a float-to-int conversion at this dialect's
  16-bit INTEGER width, so it destroys any value outside -32767..32767. This
  is how an integer literal's value is read out of the AST. }
FUNCTION pas_double_to_int64(val: REAL): CLONG [C];
FUNCTION LLVMConstReal(ty: ADRMEM; n: REAL): ADRMEM [C];
FUNCTION LLVMAddGlobal(m: ADRMEM; ty: ADRMEM; name: ADRMEM): ADRMEM [C];
PROCEDURE LLVMSetInitializer(gvar: ADRMEM; val: ADRMEM) [C];
{ Constant-expression and global-variable shaping, used by the kernel launch
  registry: parallel name/entry tables and the i8**/i8**/i64 struct
  pointing at them. }
FUNCTION LLVMConstArray(elem_ty: ADRMEM; vals: ADRMEM; count: CINT): ADRMEM [C];
FUNCTION LLVMConstStructInContext(ctx: ADRMEM; vals: ADRMEM; count: CINT; is_packed: CINT): ADRMEM [C];
FUNCTION LLVMConstBitCast(val: ADRMEM; ty: ADRMEM): ADRMEM [C];
FUNCTION LLVMConstPointerNull(ty: ADRMEM): ADRMEM [C];
PROCEDURE LLVMSetGlobalConstant(gvar: ADRMEM; is_constant: CINT) [C];
PROCEDURE LLVMSetLinkage(v: ADRMEM; linkage: CINT) [C];
FUNCTION LLVMGetNamedGlobal(m: ADRMEM; name: ADRMEM): ADRMEM [C];
PROCEDURE LLVMSetThreadLocal(gvar: ADRMEM; is_tl: CINT) [C];
  { get-or-create + external-linkage + thread-local, used to reference the
    CPU device shim's TLS index registers (__pas_tid_x etc., cpu_device_shim.c)
    from a host-triple compiland, rather than defining a fresh module-local
    copy of them. }
FUNCTION LLVMBuildLoad2(b: ADRMEM; ty: ADRMEM; ptr: ADRMEM; name: ADRMEM): ADRMEM [C];
PROCEDURE LLVMBuildStore(b: ADRMEM; val: ADRMEM; ptr: ADRMEM) [C];
PROCEDURE LLVMSetAlignment(v: ADRMEM; bytes: CINT) [C];
  { Applies to an alloca/load/store instruction. Needed by the SysV
    register-coercion paths, which read and write an aggregate's storage
    through eightbyte-wide piece types whose own ABI alignment can exceed
    the aggregate's -- exactly what clang spells as `load i64, ptr %s,
    align 4` for a two-INTEGER32 struct. }
FUNCTION LLVMBuildAdd(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildSub(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildMul(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildSDiv(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildSRem(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFAdd(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFSub(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFMul(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFDiv(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildAnd(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildOr(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildXor(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildNot(b: ADRMEM; val: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildShl(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildLShr(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildUDiv(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildURem(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildExtractValue(b: ADRMEM; agg: ADRMEM; idx: CINT; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildInsertValue(b: ADRMEM; agg: ADRMEM; elt: ADRMEM; idx: CINT; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildICmp(b: ADRMEM; pred: CINT; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildSelect(b: ADRMEM; cond: ADRMEM; thenv: ADRMEM; elsev: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFCmp(b: ADRMEM; pred: CINT; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildSExt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildSIToFP(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFPToSI(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFPExt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildFPTrunc(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMFloatTypeInContext(ctx: ADRMEM): ADRMEM [C];
PROCEDURE LLVMBuildBr(b: ADRMEM; dest: ADRMEM) [C];
PROCEDURE LLVMBuildCondBr(b: ADRMEM; cond: ADRMEM; then_bb: ADRMEM; else_bb: ADRMEM) [C];
FUNCTION LLVMBuildPhi(b: ADRMEM; ty: ADRMEM; name: ADRMEM): ADRMEM [C];
PROCEDURE LLVMAddIncoming(phi: ADRMEM; vals: ADRMEM; blocks: ADRMEM; count: CINT) [C];
FUNCTION LLVMGetInsertBlock(b: ADRMEM): ADRMEM [C];
FUNCTION LLVMGetBasicBlockTerminator(bb: ADRMEM): ADRMEM [C];
FUNCTION LLVMGetEntryBasicBlock(fn: ADRMEM): ADRMEM [C];
FUNCTION LLVMGetFirstInstruction(bb: ADRMEM): ADRMEM [C];
PROCEDURE LLVMPositionBuilderBefore(b: ADRMEM; instr: ADRMEM) [C];
FUNCTION LLVMBuildCall2(b: ADRMEM; fty: ADRMEM; fn: ADRMEM; args: ADRMEM; nargs: CINT; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMBuildRet(b: ADRMEM; v: ADRMEM): ADRMEM [C];
PROCEDURE LLVMBuildRetVoid(b: ADRMEM) [C];
FUNCTION LLVMBuildAlloca(b: ADRMEM; ty: ADRMEM; name: ADRMEM): ADRMEM [C];
FUNCTION LLVMGetParam(fn: ADRMEM; idx: CINT): ADRMEM [C];
FUNCTION LLVMVoidTypeInContext(ctx: ADRMEM): ADRMEM [C];
FUNCTION LLVMPrintModuleToString(m: ADRMEM): ADRMEM [C];
PROCEDURE LLVMInitializeNVPTXTargetInfo [C];
PROCEDURE LLVMInitializeNVPTXTarget [C];
PROCEDURE LLVMInitializeNVPTXTargetMC [C];
PROCEDURE LLVMInitializeNVPTXAsmPrinter [C];
FUNCTION LLVMGetTargetFromTriple(triple: ADRMEM; target_out: ADRMEM; error_out: ADRMEM): CINT [C];
FUNCTION LLVMCreateTargetMachine(target: ADRMEM; triple, cpu, features: ADRMEM; opt_level, reloc, code_model: CINT): ADRMEM [C];
FUNCTION LLVMCreateTargetDataLayout(tm: ADRMEM): ADRMEM [C];
PROCEDURE LLVMSetModuleDataLayout(m, layout: ADRMEM) [C];
FUNCTION LLVMTargetMachineEmitToMemoryBuffer(tm, m: ADRMEM; filetype: CINT; error_out, buffer_out: ADRMEM): CINT [C];
FUNCTION LLVMGetBufferStart(buffer: ADRMEM): ADRMEM [C];
PROCEDURE LLVMDisposeMemoryBuffer(buffer: ADRMEM) [C];
PROCEDURE LLVMDisposeTargetMachine(tm: ADRMEM) [C];
FUNCTION LLVMVerifyModule(m: ADRMEM; action: CINT; outmsg: ADRMEM): CINT [C];
FUNCTION malloc(size: CINT): ADRMEM [C];
PROCEDURE free(p: ADRMEM) [C];
FUNCTION puts(str: ADRMEM): CINT [C];
PROCEDURE exit(code: CINT) [C];
FUNCTION getenv(name: ADRMEM): ADRMEM [C];
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C];
FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C];
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C];


{ SysV MEMORY-class byval/align attribute emission for [C] FOREIGN aggregate
  parameters (see EmitByvalAttrsForParam / SysVAggClass below). Modern LLVM
  requires a *typed* byval attribute, hence LLVMCreateTypeAttribute rather
  than the older untyped enum-only form. }
FUNCTION LLVMGetEnumAttributeKindForName(name: ADRMEM; slen: CLONG): CINT [C];
FUNCTION LLVMCreateEnumAttribute(ctx: ADRMEM; kind_id: CINT; val: CLONG): ADRMEM [C];
FUNCTION LLVMCreateTypeAttribute(ctx: ADRMEM; kind_id: CINT; ty: ADRMEM): ADRMEM [C];
PROCEDURE LLVMAddCallSiteAttribute(call: ADRMEM; idx: CINT; attr: ADRMEM) [C];
PROCEDURE LLVMAddAttributeAtIndex(fn: ADRMEM; idx: CINT; attr: ADRMEM) [C];

CONST
  LLVMAbortProcessAction = 0;

  LLVMIntEQ  = 32; LLVMIntNE  = 33;
  LLVMIntSGT = 38; LLVMIntSGE = 39; LLVMIntSLT = 40; LLVMIntSLE = 41;

  LLVMRealOEQ = 1; LLVMRealOGT = 2; LLVMRealOGE = 3;
  LLVMRealOLT = 4; LLVMRealOLE = 5; LLVMRealONE = 6;

  TK_UNKNOWN = 0;
  TK_INTEGER = 1;
  TK_REAL    = 2;
  TK_BOOLEAN = 3;
  TK_CHAR    = 4;
  TK_WORD    = 5; { 16-bit, same LLVM type (i16) as TK_INTEGER -- distinguished
    only by this tag, used for WRITE's %u-vs-%d formatting and the vintage
    "INTEGER constant assigns to WORD" rule. Per the Python reference,
    same-width WORD arithmetic (DIV/MOD/comparisons) still uses *signed*
    LLVM instructions (sdiv/srem/icmp signed), not unsigned ones -- only
    WRITE formatting and (in the reference, not replicated here since this
    file has no cross-width promotion at all) widening-extend choice are
    signedness-aware. }
  TK_INTEGER8 = 6; { 8-bit signed, LLVM i8 (same width as TK_CHAR, distinct
    tag). Unlike the Python reference, this file has no feature-gate
    mechanism, so INTEGER8 is always available here rather than gated
    behind -f wide-integers. }
  TK_WORD8    = 7;  { 8-bit unsigned, LLVM i8 -- the unsigned sibling of
    INTEGER8, printed via %u like WORD. }
  TK_INTEGER32 = 8;  { 32-bit signed, LLVM i32. }
  TK_WORD32    = 9;  { 32-bit unsigned, LLVM i32, printed via %u. }
  TK_INTEGER64 = 10; { 64-bit signed, LLVM i64, printed via %lld. }
  TK_WORD64    = 11; { 64-bit unsigned, LLVM i64, printed via %llu. }
  TK_REAL32    = 12; { 32-bit float, LLVM float -- REAL32 widens implicitly
    into REAL (fpext) on assignment; the reverse is not implicit, matching
    the Python reference, except this file additionally allows a bare REAL
    literal to narrow (fptrunc) into a REAL32 target, mirroring the same
    literal-only looseness INTEGER8 already gets relative to the reference
    (see CoerceForAssign) since this file's literal codegen has no
    context-type threading to make RealLiteral itself REAL32-typed. }
  TK_ADRMEM  = 13; { opaque FFI pointer type, LLVM i8*, printed nowhere --
    the same tag used pervasively by the native compiler stages themselves
    (lexer.pas/parser.pas/typechecker.pas) as the cJSON/[C]EXTERN handle
    type; maps to the same i8ptrty global already used for TK_POINTER's
    underlying LLVM representation, but kept as its own bare-scalar tid
    (not a `types[]` entry) since it has no element/field structure. }
  { ids 1..13 are the bare scalar kinds (INTEGER/REAL/BOOLEAN/CHAR/WORD/
    INTEGER8/WORD8/INTEGER32/WORD32/INTEGER64/WORD64/REAL32/ADRMEM); ids 14+
    are markers whose real tid is an index into `types` (see TypeKind/
    LLVMTypeForTk) -- bumped up from the original 7 to make room for the
    rest of the wide-integer/REAL32/ADRMEM extension family. }
  TK_ARRAY   = 14;
  TK_RECORD  = 15;
  TK_LSTRING = 16;
  TK_POINTER = 17;
  TK_STRING  = 18;
  TK_SET     = 19;
  TK_FILE    = 20; { elem_tid holds the element type (CHAR for TEXT); .hi
    repurposed as the structure flag, 0 = BINARY (FILE OF T) / 1 = ASCII
    (the predeclared TEXT type) -- mirrors the reference's FCB `structure`
    field and typechecker.pas's own aux2 repurposing for the same fact.
    The variable's own storage (llvm_ty) is always a bare i8* pointing at a
    separately entry-alloca'd FCB + inline buffer, matching the reference's
    _init_file_storage: the handle the rest of codegen sees is opaque. }
  TK_ENUM    = 21; { a user-declared enumerated type -- always a types[]
    entry (tid >= 14), never a bare tid: i32 storage holding the 0-based
    ordinal, member identifiers registered in const_tbl (see the
    ResolveTypeExpr EnumType case). The manual reads enumerated values as
    numbers and writes them that way too by default (13610-13618), so an
    enum participates in I/O exactly like an INTEGER32. }

  MAX_SYMBOLS = 500;
  MAX_SCOPES = 64;
  MAX_PARAMS = 16;
  MAX_SYSV_LEAVES = 32; { Upper bound on the scalar leaves of an aggregate the
    SysV classifier ever walks: it only runs on types of at most 16 bytes and
    the smallest leaf is 1 byte, so 16 is the true maximum; 32 leaves headroom
    and the walker aborts loudly rather than truncating if it is ever hit. }
  MAX_ROUTINES = 384;
  MAX_TYPES = 200;
  MAX_FIELDS = 500;
  MAX_RECORD_FIELDS = 32;
  MAX_LABELS = 64; { GOTO targets within a single routine -- generous against
    real self-hosting sources, which use none, and this dialect's own
    MAX_STMT_DEPTH=256 nesting ceiling bounds how many LabelStmts a routine
    body could plausibly contain. }
  MAX_CONSTS = 200;
  MAX_UNITS = 64; { distinct spliced INTERFACE headers (local_interfaces
    entries) reachable from one compiland's USES graph -- generous against
    any real program while keeping unit-graph traversal a fixed array walk,
    consistent with MAX_LABELS/MAX_ROUTINES/etc. above. }
  MAX_DEV_ROUTINES = 128; { device routines registered for the kernel-entry
    readonly summary below -- a separate, smaller table than `routines`
    because it holds AST declaration nodes (needed before any of them is
    lowered), not lowered LLVM functions. }
  MAX_KERNELS = 64; { launchable kernels recorded per host compiland for the
    launch registry (the CPU stand-in for a loaded CUDA module). }
  MAX_CALL_EDGES = 128; { formal-forwarded-to-a-call edges recorded for one
    routine body by ComputeReadonlyEffects. }

  { Pointer-identity codes (TypeRec.ptr_space). PTR_SPACE_PLAIN is `^T`; the
    rest name the ADS space written in the source. They are deliberately not
    LLVM address-space numbers -- the address space depends on the target
    (zero everywhere but NVPTX), while these do not. }
  PTR_SPACE_PLAIN = 0;
  PTR_SPACE_HOST = 1;
  PTR_SPACE_GLOBAL = 2;
  PTR_SPACE_SHARED = 3;
  PTR_SPACE_CONSTANT = 4;
  PTR_SPACE_LOCAL = 5;

TYPE
  PAdr = ^ADRMEM;

  { A type id ("tid") is either a bare scalar TK_* constant (1..4) or an
    index into `types` (5..) for an ARRAY/RECORD -- see TypeKind/
    RegisterType below. Every "tk"/"tid"-named field or parameter in this
    file holds one of these; MAX_TYPES/MAX_FIELDS are both comfortably
    under INTEGER's 16-bit range, so plain INTEGER (not INTEGER32) is
    correct here, unlike a count/size/loop-index field. }

  TypeRec = RECORD
    name: Str255;    { the TYPE decl's name that introduced this entry, ''
                        for an anonymous inline ARRAY/RECORD type_expr }
    tk: INTEGER;      { TK_ARRAY or TK_RECORD }
    elem_tid: INTEGER; { ARRAY only: the element type's id }
    lo, hi: INTEGER;   { ARRAY only: the index range's bounds }
    is_super: BOOLEAN; { SUPER ARRAY is represented as a flat element pointer }
    ptr_space: INTEGER; { POINTER only: PTR_SPACE_PLAIN for `^T`, or the
                          PTR_SPACE_* code of an ADS pointer's space. Part of
                          the pointer's identity for assignment compatibility,
                          independently of the LLVM address space, which is
                          zero for every space outside an NVPTX compiland. }
    llvm_ty: ADRMEM;   { the cached LLVMTypeRef for this type }
  END;

  FieldRec = RECORD
    rec_tid: INTEGER;
    fname: Str255;
    field_tid: INTEGER;
    field_index: INTEGER; { 0-based LLVM struct member for fixed records }
    byte_offset: INTEGER32; { explicit offset; variant arms may overlap }
  END;

  ConstRec = RECORD
    name: Str255;
    ival: INTEGER64; { the folded value for a plain (optionally negated)
                        integer-literal CONST -- see CodegenConstDecl --
                        mirroring the Python reference's eval_const_expr/
                        self.constants side table rather than materializing
                        a real LLVM global for each. }
    is_real: BOOLEAN; { TRUE if this CONST was instead a (optionally
                         negated) REAL literal, e.g. `CONST RADIX = 1.0e9;`
                         -- rval holds its value in that case, ival unused. }
    is_char: BOOLEAN; { TRUE if this CONST was a CHAR literal, e.g.
                         `CONST TAB = CHR(9)`'s literal cousin `CONST
                         SPACE = ' '`. ival holds the ordinal, exactly as
                         for an integer CONST, so every numeric use (array
                         bounds, set ranges, ORD) keeps working unchanged;
                         this flag only tells the materializing site in
                         cg_expr to rebuild the value as an i8 CHAR rather
                         than an i16 INTEGER, so that WRITELN prints a
                         character instead of its ordinal. }
    rval: REAL;
  END;

  SymRec = RECORD
    name: Str255;
    tk: INTEGER;
    llvm_val: ADRMEM; { the LLVMValueRef of the variable's storage: an
                        LLVMAddGlobal for a global, an LLVMBuildAlloca for a
                        local or a value-mode parameter, or the raw incoming
                        pointer argument itself for a VAR-mode parameter --
                        all three are just opaque pointers to CodegenExpr's
                        LLVMBuildLoad2/LLVMBuildStore call sites, so no
                        separate "kind" tag is needed. }
  END;

  ParamNameArr = ARRAY [1..MAX_PARAMS] OF Str255;
  ParamTkArr = ARRAY [1..MAX_PARAMS] OF INTEGER;
  ParamVarArr = ARRAY [1..MAX_PARAMS] OF BOOLEAN;

  { SysV AMD64 aggregate classification working/result storage. An aggregate
    that is not MEMORY class is at most 16 bytes, i.e. at most two eightbytes,
    so the per-eightbyte result arrays have exactly two slots. }
  SysVPieceArr = ARRAY [1..2] OF INTEGER;
  SysVPieceSzArr = ARRAY [1..2] OF INTEGER32;
  SysVFlagArr = ARRAY [1..2] OF BOOLEAN;
  SysVLeafOffArr = ARRAY [1..MAX_SYSV_LEAVES] OF INTEGER32;
  SysVLeafTidArr = ARRAY [1..MAX_SYSV_LEAVES] OF INTEGER;

  RoutineRec = RECORD
    name: Str255;
    is_func: BOOLEAN;
    fn: ADRMEM;
    fnty: ADRMEM;
    ret_tk: INTEGER;
    nparams: INTEGER32;
    param_tk: ParamTkArr;
    param_is_var: ParamVarArr;
    param_needs_copy: ParamVarArr; { TRUE for a value-mode (no VAR/CONST)
                                     ARRAY/RECORD/LSTRING/STRING param: still
                                     passed as a pointer at the ABI level
                                     (like param_is_var), but the callee
                                     memcpy's it into a fresh local copy on
                                     entry instead of aliasing the caller's
                                     storage, matching Pascal value-parameter
                                     semantics for an aggregate too large to
                                     pass as a raw LLVM value. }
    has_body: BOOLEAN; { FALSE for a FORWARD/EXTERN placeholder that hasn't
                          yet been (or, for EXTERN, never will be) followed
                          by its real Block-bodied definition. }
    is_c: BOOLEAN; { TRUE for an EXTERN/EXTERNAL routine carrying the [C]
                      attribute -- see IsCForeignDecl. A needs_copy param of
                      such a routine crosses the C ABI as SysV MEMORY-class
                      byval, not as the plain-Pascal first-class-aggregate
                      convention the rest of param_needs_copy documents. }
    is_extern: BOOLEAN; { TRUE when this routine was declared EXTERN/EXTERNAL
                          (the directive, or the [C]/[EXTERN] attribute form).
                          Its body lives in another compiland, so -- unlike a
                          FORWARD placeholder, which has_body=FALSE cannot
                          distinguish it from -- a later Block-bodied
                          declaration of the same name is an error rather
                          than the completion of the placeholder. }
    is_vararg: BOOLEAN; { TRUE for a [C] EXTERN routine carrying the
                          [VARARGS] attribute -- see IsVarargsDecl. nparams
                          is then only the FIXED prefix: the LLVM function
                          type is variadic, a call may pass extra trailing
                          arguments, and each of those gets C's default
                          argument promotions applied (CodegenCallCommon). }
  END;

  LabelRec = RECORD
    name: Str255; { normalized key for both spellings a label can take --
                    an identifier as-is, or an integer label's decimal text
                    (see LabelKey) -- since the JSON 'label' field on
                    GotoStmt/LabelStmt/BreakStmt/CycleStmt is polymorphic. }
    block: ADRMEM;
  END;

VAR
  ctx, modl, builder: ADRMEM;
  i32ty, i16ty, i8ty, i1ty, i64ty, dblty, f32ty, i8ptrty, voidty: ADRMEM;
  setty: ADRMEM; { the one physical set representation shared by every SET
                   type regardless of declared base range, matching the
                   Python reference's set_llvm_type: a fixed [4 x i64]
                   256-bit bitvector. }
  generic_set_tid: INTEGER; { lazily registered the first time a "set value
                   with no single declared named type" is produced (a set
                   constructor's result, or a set binop's result) -- see
                   EnsureGenericSetType. Every SET type shares the same
                   physical layout, so operations that mix two differently
                   *named* set types (or an anonymous constructor value with
                   a named one) are still valid; TypesCompatibleForAssign
                   below is what actually allows that, this tid just needs
                   to be *some* valid registered TK_SET entry to satisfy
                   TypeKind's table lookup. }
  main_fnty, main_fn, entry_bb: ADRMEM;
  printf_fnty, printf_fn: ADRMEM;
  malloc_fnty, malloc_fn, free_fnty, free_fn: ADRMEM; { the *target program's*
    malloc/free, declared+called as ordinary LLVM externs -- distinct from
    this compiler's own host-side `malloc`/`free` FFI used by AllocPtrArray
    and friends. NEW/DISPOSE must emit a runtime call instruction, not
    allocate on the compiler's own process heap. }
  memmove_fnty, memmove_fn: ADRMEM;
  launch_fnty, launch_fn: ADRMEM; { CPU-device launch shim: entry, six
                                  i64 geometry values, and void** argv. }
  dev_alloc_fnty, dev_alloc_fn: ADRMEM;
  dev_copy_to_fnty, dev_copy_to_fn: ADRMEM;
  dev_copy_from_fnty, dev_copy_from_fn: ADRMEM;
  dev_free_fnty, dev_free_fn: ADRMEM; { host-only device-memory orchestration:
    DEVALLOC/DEVCOPYTO/DEVCOPYFROM/DEVFREE, declared+called against
    pas_dev_alloc/copy_to/copy_from/free exactly like malloc/free above --
    the CPU shim's stand-ins (malloc/memcpy/free) today, the real CUDA
    driver path when linked against cuda_launch.c instead. }
  filefcbty: ADRMEM; { the file-control-block layout, matching the reference's
    file_fcb_type and runtime/pascalrt.h's struct pas_file_fcb exactly:
    i32 elem_size, i32 structure, i32 touched, i32 mode, i8* buffer,
    i8* handle, i8* name, i32 filemode, i8 trap, i32 errs -- ten fields,
    in that order. }
  file_reset_fnty, file_reset_fn: ADRMEM;
  file_rewrite_fnty, file_rewrite_fn: ADRMEM;
  file_get_fnty, file_get_fn: ADRMEM;
  file_put_fnty, file_put_fn: ADRMEM;
  file_close_fnty, file_close_fn: ADRMEM;
  file_discard_fnty, file_discard_fn: ADRMEM;
  file_assign_fnty, file_assign_fn: ADRMEM;
  file_eof_fnty, file_eof_fn: ADRMEM;
  file_eoln_fnty, file_eoln_fn: ADRMEM;
  file_buffer_fnty, file_buffer_fn: ADRMEM; { F^ buffer variable access. }
  file_touch_buffer_fnty, file_touch_buffer_fn: ADRMEM;
  args_init_fnty, args_init_fn: ADRMEM; { argv-bound program-heading
    parameters (manual 13-5..13-7): pas_args_init/pas_arg_begin/pas_arg_end,
    runtime/cmdline.c's command-line/keyboard-fallback reader. }
  arg_begin_fnty, arg_begin_fn: ADRMEM;
  arg_end_fnty, arg_end_fn: ADRMEM;
  main_argc_val, main_argv_val: ADRMEM; { main's own (argc, argv) params,
    captured once so CodegenProgramParameters can hand them to
    pas_args_init after declarations (and their file storage) exist. }
  write_fmt_fnty, write_fmt_fn: ADRMEM; { pas_write_fmt(fcb*, fmt, ...) --
    the file-targeted counterpart of printf_fn above, same varargs shape. }
  fread_int_fnty, fread_int_fn: ADRMEM;
  fread_word_fnty, fread_word_fn: ADRMEM;
  fread_ptr_fnty, fread_ptr_fn: ADRMEM; { pointer-as-number READ, the manual's
    implementation-defined round-trip format (13620-13623). }
  fread_enum_name_fnty, fread_enum_name_fn: ADRMEM; { BOOLEAN-by-name-or-number
    READ from a file (manual 13610-13618). }
  fread_real_fnty, fread_real_fn: ADRMEM;
  fread_char_fnty, fread_char_fn: ADRMEM;
  fread_lstring_fnty, fread_lstring_fn: ADRMEM;
  fread_string_fnty, fread_string_fn: ADRMEM;
  freadln_skip_fnty, freadln_skip_fn: ADRMEM;
  freadset_fnty, freadset_fn: ADRMEM; { pas_freadset(fcb*, lstr*, cap, set_words*) }
  file_attach_std_fnty, file_attach_std_fn: ADRMEM; { pas_file_attach_std(in_fcb*, out_fcb*) }
  read_int_fnty, read_int_fn: ADRMEM; { stdin counterparts (readq.c), used by
    a bare READ/READLN with no leading file argument. }
  read_word_fnty, read_word_fn: ADRMEM;
  read_ptr_fnty, read_ptr_fn: ADRMEM; { stdin counterparts of the two above. }
  read_enum_name_fnty, read_enum_name_fn: ADRMEM;
  read_real_fnty, read_real_fn: ADRMEM;
  read_char_fnty, read_char_fn: ADRMEM;
  read_lstring_fnty, read_lstring_fn: ADRMEM;
  read_string_fnty, read_string_fn: ADRMEM;
  readln_skip_fnty, readln_skip_fn: ADRMEM;
  byval_kind_id, align_kind_id: CINT; { LLVM enum attribute kind ids for the
    [C] FOREIGN MEMORY-class byval call marshalling below, resolved once at
    init time (see byval_align_kinds_init) rather than re-resolving by name
    on every call site/declaration. }
  sret_kind_id: CINT; { and, for a MEMORY-class aggregate RETURN, the hidden
    result-pointer parameter's `sret(ty)` -- a TYPE attribute like byval, not
    a bare enum one, so it is built with LLVMCreateTypeAttribute. }
  readonly_kind_id, nocapture_kind_id, noalias_kind_id: CINT;
  deref_kind_id: CINT; { and the kernel-entry parameter facts (readonly,
    nocapture, noalias, dereferenceable), resolved the same way. }
  captures_kind_id: CINT; { LLVM >= 20 replaced the bare `nocapture` enum
    attribute with `captures(CaptureInfo)`; captures(none) is the same
    zero-valued enum attribute encoding nocapture used, just under the new
    name, so this is the fallback when nocapture_kind_id resolves to 0. }
  noalias_kernel_params: BOOLEAN; { the LAUNCH contract's
    distinct-buffers-don't-overlap fact. Off unless PASCAL_NOALIAS_KERNEL_PARAMS
    is set in the environment: it is a policy assertion about the caller, not
    something this compiler can prove, so it must be opted into explicitly
    (the native counterpart of the reference's -f noalias-kernel-params). }
  module_load_fnty, module_load_fn: ADRMEM;
  module_getfn_fnty, module_getfn_fn: ADRMEM; { the two module-resolution
    steps of the launch path (cuModuleLoadData / cuModuleGetFunction). }
  device_backend_cuda: BOOLEAN; { PASCAL_DEVICE_BACKEND=cuda: the kernel is
    the loaded PTX module, dispatched by name, so no in-process registry or
    dispatch thunk is emitted and the PTX blob is an external symbol. }
  klaunch_registry_gv, klaunch_registry_ty: ADRMEM; { this compiland's
    registry global, created on first LAUNCH and initialized once every
    LAUNCH has been lowered. }
  device_ptx_gv, device_ptx_ptr_val: ADRMEM;
  nkernels: INTEGER32;
  kernel_name_tab: ARRAY [1..MAX_KERNELS] OF Str255;
  kernel_thunk_tab: ARRAY [1..MAX_KERNELS] OF ADRMEM;
  dev_ro_count: INTEGER32;
  dev_ro_name: ARRAY [1..MAX_DEV_ROUTINES] OF Str255;
  dev_ro_decl: ARRAY [1..MAX_DEV_ROUTINES] OF ADRMEM;
  dev_ro_dup: ARRAY [1..MAX_DEV_ROUTINES] OF BOOLEAN;
  dev_ro_nparams: ARRAY [1..MAX_DEV_ROUTINES] OF INTEGER32;
  dev_ro_cached: ARRAY [1..MAX_DEV_ROUTINES] OF BOOLEAN;
  dev_ro_busy: ARRAY [1..MAX_DEV_ROUTINES] OF BOOLEAN;
  dev_ro_mask: ARRAY [1..MAX_DEV_ROUTINES] OF ParamVarArr; { entry i TRUE =
    the i'th formal of that declaration is proven never written through and
    never captured; see DeviceReadonlySummary. }
  eff_nparams: INTEGER32; { ComputeReadonlyEffects's output, in globals rather
    than VAR parameters because the walk itself is recursive: a caller copies
    these out before recursing into another routine's summary. }
  eff_pname: ParamNameArr;
  eff_written, eff_escaped: ParamVarArr;
  eff_has_with: BOOLEAN;
  eff_ncalls: INTEGER32;
  eff_call_formal: ARRAY [1..MAX_CALL_EDGES] OF INTEGER32;
  eff_call_callee: ARRAY [1..MAX_CALL_EDGES] OF Str255;
  eff_call_argpos: ARRAY [1..MAX_CALL_EDGES] OF INTEGER32;
  memcmp_fnty, memcmp_fn: ADRMEM; { for whole-string EQ/NEQ/LT/LE/GT/GE comparisons. }
  positn_fnty, positn_fn: ADRMEM;
  scaneq_fnty, scaneq_fn: ADRMEM;
  scanne_fnty, scanne_fn: ADRMEM;
  encode_fnty, encode_fn: ADRMEM;
  decode_fnty, decode_fn: ADRMEM; { the target program's runtime-library
    string builtins (INSERT/DELETE via libc's memmove; POSITN/SCANEQ/SCANNE/
    ENCODE/DECODE via libpascalrt's positn/scaneq/scanne/encode_value/
    decode_value, declared+called exactly like malloc/free/printf above --
    a program built from this file's output must link libpascalrt.a, same
    as one built from the Python reference's output already must. }
  sqrt_fnty, sqrt_fn, sin_fnty, sin_fn, cos_fnty, cos_fn: ADRMEM;
  log_fnty, log_fn, exp_fnty, exp_fn, atan_fnty, atan_fn: ADRMEM; { REAL->REAL
    libm functions backing SQRT/SIN/COS/LN/EXP/ARCTAN, declared+called as
    ordinary LLVM externs against libm exactly like malloc/printf are
    against libc -- a program built from this file's output must link -lm,
    same as one built from the Python reference's output already must. }
  cur_fn: ADRMEM; { the LLVM function LLVMAppendBasicBlockInContext should
                    attach new blocks to: main_fn at top level, or the
                    routine currently being codegen'd. }
  is_device_compiland: BOOLEAN; { fixed for the root compilation unit; type
                                   lowering needs it before routine codegen. }
  is_nvptx_device: BOOLEAN; { true only when this DEVICE compiland targets
                               nvptx64-nvidia-cuda. }

  types: ARRAY [1..MAX_TYPES] OF TypeRec;
  ntypes: INTEGER; { MAX_TYPES=200 is well under INTEGER's 16-bit range, so
                     unlike nsymbols/nroutines this stays plain INTEGER --
                     matches every tid value it produces, which also flow
                     into plain-INTEGER tk/tid fields (SymRec.tk,
                     TypeRec.elem_tid, RoutineRec.param_tk, ...); mixing
                     INTEGER32 in here would just create narrowing-assignment
                     friction against those fields for no value-range benefit. }
  fields: ARRAY [1..MAX_FIELDS] OF FieldRec;
  nfields: INTEGER;

  symbols: ARRAY [1..MAX_SYMBOLS] OF SymRec;
  nsymbols: INTEGER32;
  scope_stack: ARRAY [1..MAX_SCOPES] OF INTEGER32;
  scope_top: INTEGER32;
  in_local_scope: BOOLEAN; { FALSE while codegen'ing top-level VAR decls
                             (global storage), TRUE while inside a routine
                             body (alloca'd local storage). }
  lowering_spliced_interface: BOOLEAN;
  defining_implementation: BOOLEAN;

  routines: ARRAY [1..MAX_ROUTINES] OF RoutineRec;
  nroutines: INTEGER32;

  const_tbl: ARRAY [1..MAX_CONSTS] OF ConstRec;
  nconsts: INTEGER32;

  cur_func_name: Str255; { '' unless codegen'ing a FUNCTION body, in which
                           case it is that function's own name -- mirrors
                           typechecker.pas's cur_func_name: `Name := expr`
                           inside a FUNCTION's own body assigns through the
                           return-value slot rather than any symbol-table
                           entry, and (as in typechecker.pas) the function's
                           own name is deliberately never registered as a
                           symbol, so a recursive call resolves through the
                           routine table instead of being shadowed. }
  cur_func_ret_tk: INTEGER;
  cur_func_ret_slot: ADRMEM;

  loop_break_blocks: ARRAY [1..32] OF ADRMEM; { one entry per lexically
                                                enclosing WHILE/REPEAT/FOR,
                                                pushed/popped around each
                                                loop's body so BREAK/CYCLE can
                                                branch to the right block. }
  loop_cycle_blocks: ARRAY [1..32] OF ADRMEM;
  loop_labels: ARRAY [1..32] OF Str255; { '' unless the loop at this depth is
                                          prefixed by a label (`lbl: FOR ...`),
                                          in which case a labeled BREAK/CYCLE
                                          naming it can target this depth
                                          instead of only the innermost loop. }
  loop_depth: INTEGER32;

  labels: ARRAY [1..MAX_LABELS] OF LabelRec; { every LABEL target reachable by
    GOTO within the routine currently being codegen'd, collected up front by
    SetupFunctionLabels so a forward GOTO can branch to a block that doesn't
    exist yet in program-text order. Routine-local: cleared and rebuilt at
    the start of every PROGRAM/PROCEDURE/FUNCTION/unit-init body, matching
    the Python reference's own per-routine label_blocks. }
  nlabels: INTEGER32;
  cur_routine_has_labels: BOOLEAN; { CodegenStmtArray consults this to decide
    whether code after a terminated block might still be a live GOTO target
    (see its own comment) rather than genuinely dead. }
  pending_loop_label: Str255; { set by CodegenLabelStmt just before it
    descends into an inner WhileStmt/RepeatStmt/ForStmt, consumed (and
    cleared) by that loop's own codegen procedure when it pushes loop_depth;
    '' for an unlabeled loop. }

  last_val_tk: INTEGER; { side-channel result of CodegenExpr, mirroring the
                          typechecker's own aux-field convention: the dialect
                          has no tuple returns, so the type of the most
                          recently codegen'd expression is communicated back
                          through this global rather than threaded as a var
                          parameter through every call site. }

  { Unit dependency graph: built once per compiland by BuildUnitInitOrder
    from local_interfaces (each spliced INTERFACE header's own 'uses'
    clause), consumed both for cycle diagnostics (CheckUsesClauses) and to
    drive dependency-ordered pascal_init_<unit> calls out of a PROGRAM's
    main (CodegenProgramUnitInits). A post-order DFS visit sequence is
    already a dependency-before-dependent order, so no separate reversal
    step is needed. }
  unit_order: ARRAY [1..MAX_UNITS] OF Str255; { topo order, deps before dependents }
  n_unit_order: INTEGER32;
  unit_visit_state: ARRAY [1..MAX_UNITS] OF INTEGER32; { 0=unvisited, 1=in-progress (on DFS stack), 2=done }


END;
