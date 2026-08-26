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
  WORD) and INTEGER8 (8-bit signed, tid TK_INTEGER8, LLVM i8 -- unlike the
  reference this file has no feature-gate mechanism, so INTEGER8 is always
  available rather than gated behind -f wide-integers; only a compile-time
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

(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_codegen(input, output);

USES jsonutil;

FUNCTION LLVMContextCreate: ADRMEM [C]; EXTERN;
FUNCTION LLVMModuleCreateWithNameInContext(id: ADRMEM; ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMInt32TypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMInt16TypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMInt8TypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMInt1TypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMInt64TypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMDoubleTypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMIntTypeInContext(ctx: ADRMEM; nbits: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMPointerType(elem_ty: ADRMEM; addr_space: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMArrayType(elem_ty: ADRMEM; count: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMVectorType(elem_ty: ADRMEM; count: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMStructTypeInContext(ctx: ADRMEM; elem_tys: ADRMEM; count: CINT; is_packed: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMConstNull(ty: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildGEP2(b: ADRMEM; ty: ADRMEM; ptr: ADRMEM; indices: ADRMEM; nindices: CINT; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildBitCast(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildPtrToInt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildIntToPtr(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildZExt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildTrunc(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMFunctionType(ret_ty: ADRMEM; params: ADRMEM; pcount: CINT; vararg: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMAddFunction(m: ADRMEM; name: ADRMEM; fty: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMGetNamedFunction(m: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMAppendBasicBlockInContext(ctx: ADRMEM; fn: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMCreateBuilderInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMPositionBuilderAtEnd(b: ADRMEM; bb: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMSetTarget(m: ADRMEM; triple: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMSetDataLayout(m: ADRMEM; layout: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMSetFunctionCallConv(fn: ADRMEM; cc: CINT) [C]; EXTERN;
FUNCTION LLVMMDStringInContext2(ctx: ADRMEM; str: ADRMEM; slen: CLONG): ADRMEM [C]; EXTERN;
FUNCTION LLVMMDNodeInContext2(ctx: ADRMEM; mds: ADRMEM; nmds: CLONG): ADRMEM [C]; EXTERN;
FUNCTION LLVMValueAsMetadata(v: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMMetadataAsValue(ctx: ADRMEM; md: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMAddNamedMetadataOperand(m: ADRMEM; name: ADRMEM; v: ADRMEM) [C]; EXTERN;
FUNCTION LLVMGetMDKindIDInContext(ctx: ADRMEM; name: ADRMEM; n: CINT): CINT [C]; EXTERN;
PROCEDURE LLVMSetMetadata(v: ADRMEM; kind: CINT; md: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMReplaceMDNodeOperandWith(v: ADRMEM; idx: CINT; replacement: ADRMEM) [C]; EXTERN;
FUNCTION LLVMBuildGlobalStringPtr(b: ADRMEM; str: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMConstInt(ty: ADRMEM; n: CLONG; signext: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMConstReal(ty: ADRMEM; n: REAL): ADRMEM [C]; EXTERN;
FUNCTION LLVMAddGlobal(m: ADRMEM; ty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMSetInitializer(gvar: ADRMEM; val: ADRMEM) [C]; EXTERN;
{ Constant-expression and global-variable shaping, used by the kernel launch
  registry: parallel name/entry tables and the i8**/i8**/i64 struct
  pointing at them. }
FUNCTION LLVMConstArray(elem_ty: ADRMEM; vals: ADRMEM; count: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMConstStructInContext(ctx: ADRMEM; vals: ADRMEM; count: CINT; is_packed: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMConstBitCast(val: ADRMEM; ty: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMConstPointerNull(ty: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMSetGlobalConstant(gvar: ADRMEM; is_constant: CINT) [C]; EXTERN;
PROCEDURE LLVMSetLinkage(v: ADRMEM; linkage: CINT) [C]; EXTERN;
FUNCTION LLVMGetNamedGlobal(m: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMSetThreadLocal(gvar: ADRMEM; is_tl: CINT) [C]; EXTERN;
  { get-or-create + external-linkage + thread-local, used to reference the
    CPU device shim's TLS index registers (__pas_tid_x etc., cpu_device_shim.c)
    from a host-triple compiland, rather than defining a fresh module-local
    copy of them. }
FUNCTION LLVMBuildLoad2(b: ADRMEM; ty: ADRMEM; ptr: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMBuildStore(b: ADRMEM; val: ADRMEM; ptr: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMSetAlignment(v: ADRMEM; bytes: CINT) [C]; EXTERN;
  { Applies to an alloca/load/store instruction. Needed by the SysV
    register-coercion paths, which read and write an aggregate's storage
    through eightbyte-wide piece types whose own ABI alignment can exceed
    the aggregate's -- exactly what clang spells as `load i64, ptr %s,
    align 4` for a two-INTEGER32 struct. }
FUNCTION LLVMBuildAdd(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildSub(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildMul(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildSDiv(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildSRem(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFAdd(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFSub(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFMul(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFDiv(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildAnd(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildOr(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildXor(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildNot(b: ADRMEM; val: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildShl(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildLShr(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildUDiv(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildURem(b: ADRMEM; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildExtractValue(b: ADRMEM; agg: ADRMEM; idx: CINT; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildInsertValue(b: ADRMEM; agg: ADRMEM; elt: ADRMEM; idx: CINT; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildICmp(b: ADRMEM; pred: CINT; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildSelect(b: ADRMEM; cond: ADRMEM; thenv: ADRMEM; elsev: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFCmp(b: ADRMEM; pred: CINT; lhs: ADRMEM; rhs: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildSExt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildSIToFP(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFPToSI(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFPExt(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildFPTrunc(b: ADRMEM; val: ADRMEM; destty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMFloatTypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMBuildBr(b: ADRMEM; dest: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMBuildCondBr(b: ADRMEM; cond: ADRMEM; then_bb: ADRMEM; else_bb: ADRMEM) [C]; EXTERN;
FUNCTION LLVMBuildPhi(b: ADRMEM; ty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMAddIncoming(phi: ADRMEM; vals: ADRMEM; blocks: ADRMEM; count: CINT) [C]; EXTERN;
FUNCTION LLVMGetInsertBlock(b: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMGetBasicBlockTerminator(bb: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMGetEntryBasicBlock(fn: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMGetFirstInstruction(bb: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMPositionBuilderBefore(b: ADRMEM; instr: ADRMEM) [C]; EXTERN;
FUNCTION LLVMBuildCall2(b: ADRMEM; fty: ADRMEM; fn: ADRMEM; args: ADRMEM; nargs: CINT; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMBuildRet(b: ADRMEM; v: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMBuildRetVoid(b: ADRMEM) [C]; EXTERN;
FUNCTION LLVMBuildAlloca(b: ADRMEM; ty: ADRMEM; name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMGetParam(fn: ADRMEM; idx: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMVoidTypeInContext(ctx: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION LLVMPrintModuleToString(m: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMInitializeNVPTXTargetInfo [C]; EXTERN;
PROCEDURE LLVMInitializeNVPTXTarget [C]; EXTERN;
PROCEDURE LLVMInitializeNVPTXTargetMC [C]; EXTERN;
PROCEDURE LLVMInitializeNVPTXAsmPrinter [C]; EXTERN;
FUNCTION LLVMGetTargetFromTriple(triple: ADRMEM; target_out: ADRMEM; error_out: ADRMEM): CINT [C]; EXTERN;
FUNCTION LLVMCreateTargetMachine(target: ADRMEM; triple, cpu, features: ADRMEM; opt_level, reloc, code_model: CINT): ADRMEM [C]; EXTERN;
FUNCTION LLVMCreateTargetDataLayout(tm: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMSetModuleDataLayout(m, layout: ADRMEM) [C]; EXTERN;
FUNCTION LLVMTargetMachineEmitToMemoryBuffer(tm, m: ADRMEM; filetype: CINT; error_out, buffer_out: ADRMEM): CINT [C]; EXTERN;
FUNCTION LLVMGetBufferStart(buffer: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMDisposeMemoryBuffer(buffer: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMDisposeTargetMachine(tm: ADRMEM) [C]; EXTERN;
FUNCTION LLVMVerifyModule(m: ADRMEM; action: CINT; outmsg: ADRMEM): CINT [C]; EXTERN;
FUNCTION malloc(size: CINT): ADRMEM [C]; EXTERN;
PROCEDURE free(p: ADRMEM) [C]; EXTERN;
FUNCTION puts(str: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;
FUNCTION getenv(name: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_IsNumber(item: ADRMEM): CINT [C]; EXTERN;


{ SysV MEMORY-class byval/align attribute emission for [C] FOREIGN aggregate
  parameters (see EmitByvalAttrsForParam / SysVAggClass below). Modern LLVM
  requires a *typed* byval attribute, hence LLVMCreateTypeAttribute rather
  than the older untyped enum-only form. }
FUNCTION LLVMGetEnumAttributeKindForName(name: ADRMEM; slen: CLONG): CINT [C]; EXTERN;
FUNCTION LLVMCreateEnumAttribute(ctx: ADRMEM; kind_id: CINT; val: CLONG): ADRMEM [C]; EXTERN;
FUNCTION LLVMCreateTypeAttribute(ctx: ADRMEM; kind_id: CINT; ty: ADRMEM): ADRMEM [C]; EXTERN;
PROCEDURE LLVMAddCallSiteAttribute(call: ADRMEM; idx: CINT; attr: ADRMEM) [C]; EXTERN;
PROCEDURE LLVMAddAttributeAtIndex(fn: ADRMEM; idx: CINT; attr: ADRMEM) [C]; EXTERN;

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

{ ============================== utilities ============================== }

(*$INCLUDE:'codegen_util.inc'*)

{ ============================== type model =============================== }

(*$INCLUDE:'codegen_types.inc'*)

{ ============================ symbol table ============================== }

(*$INCLUDE:'codegen_symbols.inc'*)

{ ============================== expressions =============================== }

(*$INCLUDE:'codegen_expr.inc'*)

{ ============================ WRITE/WRITELN =============================== }

(*$INCLUDE:'codegen_io.inc'*)

{ ============================== statements ================================ }

(*$INCLUDE:'codegen_stmt.inc'*)

{ ============================== declarations =============================== }

PROCEDURE CodegenDecl(decl: ADRMEM); FORWARD;

PROCEDURE CodegenDeclList(decls_arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  n := ArrSize(decls_arr);
  FOR i := 0 TO n - 1 DO
    CodegenDecl(ArrItem(decls_arr, i));
END;

FUNCTION SameIdentifier(a, b: Str255): BOOLEAN;
{ Case-insensitive identifier comparison. Symbol lookup elsewhere in this file
  is exact-case (the front end hands identifiers through unchanged), but a USES
  clause is matched against a UNIT heading written in a different file, where
  the two spellings routinely differ in case -- and mismatching them here would
  reject a program that otherwise compiles. }
VAR
  la, lb: Str255;
  i, n: INTEGER;
BEGIN
  la := a;
  lb := b;
  n := ORD(la[0]);
  FOR i := 1 TO n DO
    IF (la[i] >= 'A') AND (la[i] <= 'Z') THEN la[i] := CHR(ORD(la[i]) + 32);
  n := ORD(lb[0]);
  FOR i := 1 TO n DO
    IF (lb[i] >= 'A') AND (lb[i] <= 'Z') THEN lb[i] := CHR(ORD(lb[i]) + 32);
  SameIdentifier := la = lb;
END;

FUNCTION FindUnitIndex(local_ifaces: ADRMEM; unit_name: Str255): INTEGER32;
{ 1-based index of unit_name within local_ifaces (case-insensitive), or 0. }
VAR
  nifaces, fi: INTEGER32;
BEGIN
  FindUnitIndex := 0;
  IF local_ifaces <> NIL THEN
  BEGIN
    nifaces := ArrSize(local_ifaces);
    FOR fi := 0 TO nifaces - 1 DO
      IF SameIdentifier(GetStr(ArrItem(local_ifaces, fi), 'name'), unit_name) THEN
        FindUnitIndex := fi + 1;
  END;
END;

PROCEDURE DFSVisitUnit(local_ifaces: ADRMEM; idx: INTEGER32);
{ Post-order DFS over the USES graph rooted at local_ifaces[idx-1], recording
  a dependency-before-dependent visit order into unit_order and detecting
  cycles via unit_visit_state (0=unvisited, 1=in progress/on the current DFS
  path, 2=finished). A cycle is a USES edge back to an in-progress unit --
  reported by name rather than left to surface as a duplicate-symbol splice
  failure or (for a genuinely self-referential include graph) an infinite
  splice loop. }
VAR
  iface, uses_arr, clause: ADRMEM;
  nu, ui, dep_idx: INTEGER32;
  dep_name, this_name: Str255;
BEGIN
  IF unit_visit_state[idx] <> 2 THEN
  BEGIN
    this_name := GetStr(ArrItem(local_ifaces, idx - 1), 'name');
    IF unit_visit_state[idx] = 1 THEN
      AbortWith2('codegen: circular USES dependency detected involving unit: ', this_name);
    unit_visit_state[idx] := 1;

    iface := ArrItem(local_ifaces, idx - 1);
    uses_arr := GetObj(iface, 'uses');
    IF uses_arr <> NIL THEN
    BEGIN
      nu := ArrSize(uses_arr);
      FOR ui := 0 TO nu - 1 DO
      BEGIN
        clause := ArrItem(uses_arr, ui);
        dep_name := GetStr(clause, 'name');
        dep_idx := FindUnitIndex(local_ifaces, dep_name);
        { A dependency with no spliced header of its own is reported by
          CheckUsesClauses's own direct-USES check below; nothing further to
          traverse here. }
        IF dep_idx <> 0 THEN
          DFSVisitUnit(local_ifaces, dep_idx);
      END;
    END;

    unit_visit_state[idx] := 2;
    { A DEVICE unit never gets a pascal_init_<name> (see codegen's own
      is_device_root guard around the ImplementationUnit/ModuleUnit init
      emission): its dependencies are still walked above for cycle
      detection, but it has nothing EmitUnitInitCalls could safely call, so
      it's left out of unit_order entirely rather than becoming a call to
      an undefined symbol. }
    IF NOT GetBool(iface, 'is_device') THEN
    BEGIN
      IF n_unit_order >= MAX_UNITS THEN
        AbortWith('codegen: too many units in one USES dependency graph');
      n_unit_order := n_unit_order + 1;
      unit_order[n_unit_order] := this_name;
    END;
  END;
END;

PROCEDURE BuildUnitInitOrder(root, local_ifaces: ADRMEM);
{ Populates unit_order[1..n_unit_order] with every unit transitively reached
  from root's own USES clauses, dependencies before dependents, each named
  exactly once -- consumed by CodegenProgramUnitInits to call each unit's
  pascal_init_<name> in a safe order, and doubles as the cycle-detection pass
  for CheckUsesClauses. }
VAR
  uses_arr, clause: ADRMEM;
  nclauses, ci, idx, nifaces, i: INTEGER32;
  unit_name: Str255;
BEGIN
  n_unit_order := 0;
  IF local_ifaces <> NIL THEN
  BEGIN
    nifaces := ArrSize(local_ifaces);
    FOR i := 1 TO nifaces DO unit_visit_state[i] := 0;
  END;
  uses_arr := GetObj(root, 'uses');
  IF uses_arr <> NIL THEN
  BEGIN
    nclauses := ArrSize(uses_arr);
    FOR ci := 0 TO nclauses - 1 DO
    BEGIN
      clause := ArrItem(uses_arr, ci);
      unit_name := GetStr(clause, 'name');
      idx := FindUnitIndex(local_ifaces, unit_name);
      IF idx <> 0 THEN DFSVisitUnit(local_ifaces, idx);
    END;
  END;
END;

PROCEDURE EmitUnitInitCalls;
{ Emits a call to pascal_init_<name>() for every unit in unit_order (built
  by BuildUnitInitOrder/DFSVisitUnit from this PROGRAM's own USES graph),
  dependencies before dependents, each exactly once -- only a PROGRAM's own
  main walks the whole graph this way; a MODULE/IMPLEMENTATION compiland
  that itself USES other units does not call their inits on its own behalf,
  since that would call some units' inits more than once across a multi-unit
  link. Declares each pascal_init_<name> fresh here rather than reusing any
  existing extern: the target is defined in a *separately compiled* object
  (the unit's own IMPLEMENTATION, which -- see the is_implementation case
  below -- now always emits this function, even with an empty body, so the
  call here always has something real to link against). }
VAR
  i, j, len: INTEGER32;
  init_name, uname: Str255;
  init_fnty, init_fn, callres: ADRMEM;
BEGIN
  FOR i := 1 TO n_unit_order DO
  BEGIN
    uname := unit_order[i];
    len := ORD(uname[0]);
    FOR j := 1 TO len DO
      IF (uname[j] >= 'A') AND (uname[j] <= 'Z') THEN uname[j] := CHR(ORD(uname[j]) + 32);
    init_name := 'pascal_init_';
    CONCAT(init_name, uname);
    init_fnty := LLVMFunctionType(i32ty, NIL, 0, 0);
    init_fn := LLVMAddFunction(modl, MakeCStr(init_name), init_fnty);
    callres := LLVMBuildCall2(builder, init_fnty, init_fn, NIL, 0, MakeCStr(''));
  END;
END;

PROCEDURE BindUsesAlias(alias, ename: Str255);
{ `USES unit(alias)` binds alias to whatever ename (the export at that
  position in the unit's own heading) already resolved to when its real
  declaration was lowered under its own name a moment ago -- an *additional*
  routine-table/symbol-table entry sharing the same underlying LLVMValueRef,
  not a rename of the original. Renaming the original's own LLVM symbol
  would break linking: a UNIT's real exported symbol (the one its separately
  compiled IMPLEMENTATION object actually defines) has to keep its true
  spelling for `clang`/`ld` to resolve it, no matter what a given importer
  chooses to call it locally. Only PROCEDURE/FUNCTION and VAR exports can be
  aliased this way; TYPE/CONST renaming is not implemented (neither has a
  runtime symbol, so nothing stops a caller writing one, but no current
  fixture or Python-reference behavior needs it, and guessing at the right
  shape without one risks a silent gap of its own). }
VAR
  ri, si, i: INTEGER32;
BEGIN
  ri := LookupRoutine(ename);
  IF ri <> 0 THEN
  BEGIN
    IF nroutines >= MAX_ROUTINES THEN AbortWith('codegen: too many routines');
    nroutines := nroutines + 1;
    routines[nroutines].name := alias;
    routines[nroutines].is_func := routines[ri].is_func;
    routines[nroutines].fn := routines[ri].fn;
    routines[nroutines].fnty := routines[ri].fnty;
    routines[nroutines].ret_tk := routines[ri].ret_tk;
    routines[nroutines].nparams := routines[ri].nparams;
    FOR i := 1 TO routines[ri].nparams DO
    BEGIN
      routines[nroutines].param_tk[i] := routines[ri].param_tk[i];
      routines[nroutines].param_is_var[i] := routines[ri].param_is_var[i];
      routines[nroutines].param_needs_copy[i] := routines[ri].param_needs_copy[i];
    END;
    routines[nroutines].has_body := routines[ri].has_body;
    routines[nroutines].is_c := routines[ri].is_c;
    routines[nroutines].is_vararg := routines[ri].is_vararg;
  END
  ELSE
  BEGIN
    si := LookupSym(ename);
    IF si <> 0 THEN
    BEGIN
      IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
      nsymbols := nsymbols + 1;
      symbols[nsymbols].name := alias;
      symbols[nsymbols].tk := symbols[si].tk;
      symbols[nsymbols].llvm_val := symbols[si].llvm_val;
    END
    ELSE
      AbortWith2('codegen: USES import renames an export this compiler cannot alias (only PROCEDURE/FUNCTION/VAR are supported): ', ename);
  END;
END;

PROCEDURE CheckUsesClauses(root, local_ifaces: ADRMEM);
{ Reconcile the root's USES clauses against the INTERFACE headers spliced
  into the same source file, and (for a renaming clause) bind each alias via
  BindUsesAlias now that every local_interfaces declaration has already been
  lowered under its own real name. Also reports the other ways a USES clause
  can fail to be honored -- no spliced header for the named unit, and a
  circular USES graph -- instead of surfacing later as "unknown routine" at
  the call site or a duplicate-symbol splice failure. }
VAR
  uses_arr, clause, imports_arr, params_arr: ADRMEM;
  nclauses, ci, nifaces, fi, nimports, ii, nparams: INTEGER32;
  unit_name, alias, ename: Str255;
  found: BOOLEAN;
  matched_iface: ADRMEM;
BEGIN
  uses_arr := GetObj(root, 'uses');
  IF uses_arr <> NIL THEN
  BEGIN
    nclauses := ArrSize(uses_arr);
    FOR ci := 0 TO nclauses - 1 DO
    BEGIN
      clause := ArrItem(uses_arr, ci);
      unit_name := GetStr(clause, 'name');
      found := FALSE;
      matched_iface := NIL;
      IF local_ifaces <> NIL THEN
      BEGIN
        nifaces := ArrSize(local_ifaces);
        FOR fi := 0 TO nifaces - 1 DO
          IF SameIdentifier(GetStr(ArrItem(local_ifaces, fi), 'name'), unit_name) THEN
          BEGIN
            found := TRUE;
            matched_iface := ArrItem(local_ifaces, fi);
          END;
      END;
      IF NOT found THEN
        AbortWith2('codegen: USES unit needs a spliced INTERFACE header: ', unit_name);
      imports_arr := GetObjOrNil(clause, 'imports');
      IF imports_arr <> NIL THEN
      BEGIN
        params_arr := GetObj(matched_iface, 'params');
        nparams := ArrSize(params_arr);
        nimports := ArrSize(imports_arr);
        IF nimports > nparams THEN
          AbortWith('codegen: USES import list renames more names than the unit exports');
        FOR ii := 0 TO nimports - 1 DO
        BEGIN
          alias := CStrToStr255(cJSON_GetStringValue(ArrItem(imports_arr, ii)));
          ename := CStrToStr255(cJSON_GetStringValue(ArrItem(params_arr, ii)));
          BindUsesAlias(alias, ename);
        END;
      END;
    END;
  END;
  { Also walks the full transitive graph (not just root's direct clauses) so
    a cycle two or more hops away from root -- e.g. root USES beta USES
    alpha USES beta -- is still caught here rather than only when something
    downstream happens to walk that far. }
  BuildUnitInitOrder(root, local_ifaces);
END;

FUNCTION UpperStr(s: Str255): Str255;
VAR
  i, len: INTEGER;
  res: Str255;
  ch: CHAR;
BEGIN
  len := ORD(s[0]);
  res[0] := CHR(len);
  FOR i := 1 TO len DO
  BEGIN
    ch := s[i];
    IF (ch >= 'a') AND (ch <= 'z') THEN
      res[i] := CHR(ORD(ch) - 32)
    ELSE
      res[i] := ch;
  END;
  UpperStr := res;
END;

PROCEDURE InitFileStorage(slot: ADRMEM; elem_tid, structure: INTEGER; var_name: Str255);
{ Allocates the FCB + inline element buffer at the file variable's own
  storage site and stores an opaque i8* to the FCB into `slot` -- mirrors
  the reference's _init_file_storage field for field (see filefcbty's own
  comment for the field layout/order). INPUT/OUTPUT start pre-opened
  (mode 1); every other file starts unopened (mode 0) until RESET/REWRITE. }
VAR
  fcb, buf, gep_idx, field_ptr, zero: ADRMEM;
  elem_size, default_mode: INTEGER32;
  uname: Str255;
BEGIN
  elem_size := TypeSizeBytes(elem_tid);
  IF elem_size < 1 THEN elem_size := 1;
  fcb := EntryAlloca(filefcbty, 'file_fcb');
  buf := EntryAlloca(LLVMArrayType(i8ty, elem_size), 'file_buf');
  zero := LLVMConstInt(i32ty, 0, 0);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, elem_size, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, structure, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 2, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), field_ptr);

  uname := UpperStr(var_name);
  IF (uname = 'INPUT') OR (uname = 'OUTPUT') THEN default_mode := 1 ELSE default_mode := 0;
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 3, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, default_mode, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 4, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMBuildBitCast(builder, buf, i8ptrty, MakeCStr('')), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 5, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 6, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 7, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 8, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i8ty, 0, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 9, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), field_ptr);

  LLVMBuildStore(builder, LLVMBuildBitCast(builder, fcb, i8ptrty, MakeCStr('')), slot);
END;

PROCEDURE RegisterPredeclaredFiles;
{ Unconditionally declares INPUT/OUTPUT as TEXT-file symbols for the main
  PROGRAM, mirroring the reference's _register_predeclared_files -- without
  this, LoadFileFcbPtr('INPUT') aborts as undefined for any program that
  doesn't itself write VAR INPUT: TEXT, which is exactly the case READSET's
  2-argument implicit-INPUT form needs to cover. A no-op if the program
  already declared its own INPUT/OUTPUT (e.g. as an explicit heading
  parameter with its own VAR). }
VAR
  text_tid: INTEGER;
BEGIN
  IF LookupSym('INPUT') = 0 THEN
  BEGIN
    text_tid := RegisterType(TK_FILE, TK_CHAR, 0, 1, i8ptrty);
    DeclareVar('INPUT', text_tid);
    InitFileStorage(symbols[nsymbols].llvm_val, TK_CHAR, 1, 'INPUT');
  END;
  IF LookupSym('OUTPUT') = 0 THEN
  BEGIN
    text_tid := RegisterType(TK_FILE, TK_CHAR, 0, 1, i8ptrty);
    DeclareVar('OUTPUT', text_tid);
    InitFileStorage(symbols[nsymbols].llvm_val, TK_CHAR, 1, 'OUTPUT');
  END;
END;

PROCEDURE CodegenVarDecl(decl: ADRMEM);
VAR
  names: ADRMEM;
  tk: INTEGER;
  n, i: INTEGER32;
  vname: Str255;
BEGIN
  tk := ResolveTypeExpr(GetObj(decl, 'type_expr'));
  names := GetObj(decl, 'names');
  n := ArrSize(names);
  FOR i := 0 TO n - 1 DO
  BEGIN
    vname := CStrToStr255(cJSON_GetStringValue(ArrItem(names, i)));
    DeclareVar(vname, tk);
    IF TypeKind(tk) = TK_FILE THEN
      InitFileStorage(symbols[nsymbols].llvm_val, types[tk].elem_tid, types[tk].hi, vname);
  END;
END;

PROCEDURE ApplyLaunchBoundAttrs(decl, fn: ADRMEM);
{ NVPTX consumes launch bounds through legacy !nvvm.annotations metadata.
  They are ptxas facts, so no host-target approximation is emitted. }
VAR
  attrs, attr, args, mds, mdnode: ADRMEM;
  i, j, n, nargs: INTEGER32;
  nm, key: Str255;
BEGIN
  IF NOT is_nvptx_device THEN
    AbortWith('codegen: launch-bound attributes require an NVPTX DEVICE target');
  attrs := GetObj(decl, 'attributes');
  n := ArrSize(attrs);
  FOR i := 0 TO n - 1 DO
  BEGIN
    attr := ArrItem(attrs, i);
    nm := GetStr(attr, 'name');
    IF (nm = 'MAXNTID') OR (nm = 'REQNTID') OR (nm = 'MINCTASM') THEN
    BEGIN
      args := GetObj(attr, 'arg');
      nargs := ArrSize(args);
      FOR j := 0 TO nargs - 1 DO
      BEGIN
        IF nm = 'MAXNTID' THEN
        BEGIN
          IF j = 0 THEN key := 'maxntidx'
          ELSE IF j = 1 THEN key := 'maxntidy'
          ELSE key := 'maxntidz';
        END
        ELSE IF nm = 'REQNTID' THEN
        BEGIN
          IF j = 0 THEN key := 'reqntidx'
          ELSE IF j = 1 THEN key := 'reqntidy'
          ELSE key := 'reqntidz';
        END
        ELSE key := 'minctasm';
        mds := AllocPtrArray(3);
        SetPtrArrayElem(mds, 0, LLVMValueAsMetadata(fn));
        SetPtrArrayElem(mds, 1, LLVMMDStringInContext2(ctx, MakeCStr(key), ORD(key[0])));
        SetPtrArrayElem(mds, 2, LLVMValueAsMetadata(LLVMConstInt(i32ty, ResolveIntLiteral(ArrItem(args, j)), 0)));
        mdnode := LLVMMDNodeInContext2(ctx, mds, 3);
        LLVMAddNamedMetadataOperand(modl, MakeCStr('nvvm.annotations'), LLVMMetadataAsValue(ctx, mdnode));
      END;
    END;
  END;
END;

FUNCTION IsCForeignDecl(decl: ADRMEM): BOOLEAN;
{ True for an EXTERN/EXTERNAL routine carrying the [C] attribute -- mirrors
  the Python reference's CAbiMixin.is_c_abi_foreign (c_abi.py). Only routines
  answering TRUE here get the SysV MEMORY-class byval treatment for their
  needs_copy params (SysVAggClass below); every other routine keeps the
  plain-Pascal first-class-aggregate convention. }
VAR
  attrs_arr, item: ADRMEM;
  i, nattrs: INTEGER32;
  attr_nm, directive: Str255;
  has_c, has_extern_attr: BOOLEAN;
BEGIN
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := ArrSize(attrs_arr);
  has_c := FALSE;
  has_extern_attr := FALSE;
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    item := ArrItem(attrs_arr, i);
    { Attribute/directive names are already canonical uppercase in the AST
      (lexer keyword kinds, or the parser's own literal 'C' for [C]/[CDECL]
      -- see parser.pas ParseAttributeItem), so no case-folding is needed
      here, unlike c_abi.py's .upper() (which folds a Python-side string
      that isn't guaranteed pre-uppercased). }
    attr_nm := GetStr(item, 'name');
    { A bare `attr_nm = 'C'` comparison doesn't typecheck: single-quoted
      single-character literals lex as CHAR, not a length-1 LSTRING, so
      LSTRING = CHAR has no defined comparison. Compare the length byte
      (index 0, per the LSTRING index-0-is-length-as-CHAR convention) and
      the first character (index 1) instead -- mirrors the identical idiom
      at parser.pas:1882 for the same [C] attribute-name check. }
    IF (ORD(attr_nm[0]) = 1) AND (attr_nm[1] = 'C') THEN has_c := TRUE;
    IF (attr_nm = 'EXTERN') OR (attr_nm = 'EXTERNAL') THEN has_extern_attr := TRUE;
  END;
  directive := GetStr(decl, 'directive');
  IsCForeignDecl := has_c AND (has_extern_attr OR (directive = 'EXTERN') OR (directive = 'EXTERNAL'));
END;


FUNCTION IsVarargsDecl(decl: ADRMEM): BOOLEAN;
{ True for a routine carrying the [VARARGS] attribute -- the C variadic
  ellipsis, so the declared parameters are only the fixed prefix. Only
  meaningful on a [C] FOREIGN routine (the 1981 dialect gives a Pascal
  routine no way to read a variadic tail), so callers pair it with
  IsCForeignDecl and ignore it otherwise. The attribute name is already
  canonical uppercase in the AST, exactly as IsCForeignDecl above notes, and
  is longer than one character so it compares as a plain LSTRING. }
VAR
  attrs_arr, item: ADRMEM;
  i, nattrs: INTEGER32;
  found: BOOLEAN;
BEGIN
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := ArrSize(attrs_arr);
  found := FALSE;
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    item := ArrItem(attrs_arr, i);
    IF GetStr(item, 'name') = 'VARARGS' THEN found := TRUE;
  END;
  IsVarargsDecl := found;
END;


PROCEDURE FlattenParams(params_arr: ADRMEM; VAR n: INTEGER32; VAR names: ParamNameArr;
                         VAR tks: ParamTkArr; VAR isvar: ParamVarArr; VAR needs_copy: ParamVarArr);
{ A Pascal formal-parameter section groups several names under one type
  (`a, b: INTEGER`); this flattens that grouping into parallel arrays of
  one entry per actual parameter, matching how llvm-c's LLVMFunctionType
  and the routine table both want one slot per parameter, not one per
  group. }
VAR
  np, pi, nn, ni: INTEGER32;
  param, pnames: ADRMEM;
  tk: INTEGER;
  is_v, needs_c: BOOLEAN;
BEGIN
  n := 0;
  np := ArrSize(params_arr);
  FOR pi := 0 TO np - 1 DO
  BEGIN
    param := ArrItem(params_arr, pi);
    tk := ResolveTypeExpr(GetObj(param, 'type_expr'));
    { VAR/VARS/CONST/CONSTS are all reference-mode at the ABI level -- CONST
      only additionally forbids mutation, a typechecker-level restriction,
      not a codegen one, so it is passed the same way as VAR here: as a
      pointer, never copied. }
    is_v := (GetStr(param, 'mode') = 'VAR') OR (GetStr(param, 'mode') = 'VARS') OR
            (GetStr(param, 'mode') = 'CONST') OR (GetStr(param, 'mode') = 'CONSTS');
    { A plain value-mode ARRAY/RECORD/LSTRING/STRING param: too large to
      pass as a raw LLVM value the way a scalar is, so it is passed as a
      pointer too (see needs_copy at the routine-entry/call-site level),
      but unlike VAR/CONST the callee must copy it so mutations don't leak
      back into the caller's own storage. }
    needs_c := (NOT is_v) AND ((TypeKind(tk) = TK_ARRAY) OR (TypeKind(tk) = TK_RECORD) OR
       (TypeKind(tk) = TK_LSTRING) OR (TypeKind(tk) = TK_STRING));
    pnames := GetObj(param, 'names');
    nn := ArrSize(pnames);
    FOR ni := 0 TO nn - 1 DO
    BEGIN
      IF n >= MAX_PARAMS THEN AbortWith('codegen: too many parameters');
      n := n + 1;
      names[n] := CStrToStr255(cJSON_GetStringValue(ArrItem(pnames, ni)));
      tks[n] := tk;
      isvar[n] := is_v;
      needs_copy[n] := needs_c;
    END;
  END;
END;

FUNCTION ParamNamesOf(decl: ADRMEM; VAR names: ParamNameArr): INTEGER32;
{ Flatten one declaration's formal-parameter names only -- deliberately not
  FlattenParams, which also resolves each type_expr and so would register
  types for routines that may never be lowered. The readonly analysis below
  runs before any body is lowered and needs nothing but the names. }
VAR
  params_arr, param, pnames: ADRMEM;
  np, pi, nn, ni, n: INTEGER32;
BEGIN
  n := 0;
  params_arr := GetObj(decl, 'params');
  np := ArrSize(params_arr);
  FOR pi := 0 TO np - 1 DO
  BEGIN
    param := ArrItem(params_arr, pi);
    pnames := GetObj(param, 'names');
    nn := ArrSize(pnames);
    FOR ni := 0 TO nn - 1 DO
      IF n < MAX_PARAMS THEN
      BEGIN
        n := n + 1;
        names[n] := CStrToStr255(cJSON_GetStringValue(ArrItem(pnames, ni)));
      END;
  END;
  ParamNamesOf := n;
END;

FUNCTION ReadonlyBareFormal(node: ADRMEM): INTEGER32;
{ The 1-based formal index this node is a *bare* use of (a plain identifier,
  or a selector-less designator), or 0. A bare use of a pointer formal hands
  its raw pointer value to whatever surrounds it, so outside the one context
  that is analyzable (a direct call actual) it counts as an escape. }
VAR
  nt, nm: Str255;
  i: INTEGER32;
BEGIN
  ReadonlyBareFormal := 0;
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    nm := '';
    IF nt = 'Identifier' THEN nm := GetStr(node, 'name')
    ELSE IF nt = 'Designator' THEN
      IF ArrSize(GetObj(node, 'selectors')) = 0 THEN nm := GetStr(node, 'name');
    IF nm <> '' THEN
      FOR i := 1 TO eff_nparams DO
        IF eff_pname[i] = nm THEN ReadonlyBareFormal := i;
  END;
END;

FUNCTION AssignWritesThroughFormal(node: ADRMEM): INTEGER32;
{ For an AssignStmt, the formal index written *through* (`p^... := x`), or 0.
  A write to the pointer variable itself (`p := q`) is not a write to the
  pointee and so does not disqualify readonly; the DEREF selector is what
  distinguishes the two. }
VAR
  target, sels, sel: ADRMEM;
  i, nsel, fi: INTEGER32;
  has_deref: BOOLEAN;
  nm: Str255;
BEGIN
  AssignWritesThroughFormal := 0;
  target := GetObj(node, 'target');
  IF NodeType(target) = 'Designator' THEN
  BEGIN
    nm := GetStr(target, 'name');
    fi := 0;
    FOR i := 1 TO eff_nparams DO
      IF eff_pname[i] = nm THEN fi := i;
    IF fi <> 0 THEN
    BEGIN
      sels := GetObj(target, 'selectors');
      nsel := ArrSize(sels);
      has_deref := FALSE;
      FOR i := 0 TO nsel - 1 DO
      BEGIN
        sel := ArrItem(sels, i);
        IF GetStr(sel, 'kind') = 'DEREF' THEN has_deref := TRUE;
      END;
      IF has_deref THEN AssignWritesThroughFormal := fi;
    END;
  END;
END;

PROCEDURE ScanReadonlyNode(node: ADRMEM);
{ Accumulate one routine body's effects on its own formals into the eff_*
  globals. Everything unrecognized fails closed: a bare formal anywhere but a
  direct call actual is an escape, and a WITH anywhere disqualifies the whole
  routine (WITH's field designators are not tied back to the originating
  pointer expression by this purely syntactic walk, so a write inside a WITH
  block could otherwise go unnoticed). }
CONST
  MAX_SCAN_ARGS = 64;
VAR
  nt: Str255;
  nchild, ci, nargs, ai, fi: INTEGER32;
  args, arg: ADRMEM;
  forwarded: ARRAY [1..MAX_SCAN_ARGS] OF BOOLEAN;
BEGIN
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    { A nested routine is its own lexical body and its own call-graph node;
      its effects are summarized separately, not folded into this one. }
    IF (nt <> 'ProcDecl') AND (nt <> 'FuncDecl') THEN
    BEGIN
      IF nt = 'WithStmt' THEN eff_has_with := TRUE;
      IF nt = 'AssignStmt' THEN
      BEGIN
        fi := AssignWritesThroughFormal(node);
        IF fi <> 0 THEN eff_written[fi] := TRUE;
      END;
      IF (nt = 'FuncCall') OR (nt = 'ProcCallStmt') THEN
      BEGIN
        args := GetObj(node, 'args');
        nargs := ArrSize(args);
        FOR ai := 1 TO MAX_SCAN_ARGS DO forwarded[ai] := FALSE;
        IF nargs <= MAX_SCAN_ARGS THEN
          FOR ai := 0 TO nargs - 1 DO
          BEGIN
            arg := ArrItem(args, ai);
            fi := ReadonlyBareFormal(arg);
            IF fi <> 0 THEN
            BEGIN
              IF eff_ncalls >= MAX_CALL_EDGES THEN
                { Out of edge slots: fail closed by treating the forward as an
                  escape rather than dropping the fact on the floor. }
                eff_escaped[fi] := TRUE
              ELSE
              BEGIN
                eff_ncalls := eff_ncalls + 1;
                eff_call_formal[eff_ncalls] := fi;
                eff_call_callee[eff_ncalls] := GetStr(node, 'name');
                eff_call_argpos[eff_ncalls] := ai;
                forwarded[ai + 1] := TRUE;
              END;
            END;
          END;
        { A call node's only expression children are its actuals; the ones
          recognized as direct forwards above are summarized through the
          callee instead of being rescanned (which would call them escapes). }
        FOR ai := 0 TO nargs - 1 DO
          IF (nargs > MAX_SCAN_ARGS) OR (NOT forwarded[ai + 1]) THEN
            ScanReadonlyNode(ArrItem(args, ai));
      END
      ELSE
      BEGIN
        fi := ReadonlyBareFormal(node);
        IF fi <> 0 THEN eff_escaped[fi] := TRUE
        ELSE
        BEGIN
          { Generic descent: cJSON links an object's members and an array's
            elements through the same child list, so one loop walks both. }
          nchild := ArrSize(node);
          FOR ci := 0 TO nchild - 1 DO
            ScanReadonlyNode(ArrItem(node, ci));
        END;
      END;
    END;
  END;
END;

PROCEDURE ComputeReadonlyEffects(decl: ADRMEM);
{ Fill the eff_* globals for one declaration. Callers that then recurse into
  another routine's summary must copy the results out first. }
VAR
  i: INTEGER32;
  body: ADRMEM;
BEGIN
  eff_nparams := ParamNamesOf(decl, eff_pname);
  FOR i := 1 TO MAX_PARAMS DO
  BEGIN
    eff_written[i] := FALSE;
    eff_escaped[i] := FALSE;
  END;
  eff_has_with := FALSE;
  eff_ncalls := 0;
  body := GetObj(decl, 'body');
  IF (eff_nparams > 0) AND (NodeType(body) = 'Block') THEN
    ScanReadonlyNode(GetObj(body, 'body'));
END;

FUNCTION LookupDevRoutine(name: Str255): INTEGER32;
VAR
  i, found: INTEGER32;
BEGIN
  found := 0;
  FOR i := 1 TO dev_ro_count DO
    IF dev_ro_name[i] = name THEN found := i;
  LookupDevRoutine := found;
END;

PROCEDURE RegisterDevRoutines(decls: ADRMEM);
{ Record every body-bearing device routine, nested ones included, before any
  of them is lowered -- a kernel entry may call a helper declared later in
  the source. Body-less (interface/imported/EXTERN) declarations are left out
  so they fail closed, and a duplicate name is marked ambiguous rather than
  guessed about. }
VAR
  i, n, idx: INTEGER32;
  item, body: ADRMEM;
  nt, nm: Str255;
  pnames: ParamNameArr;
BEGIN
  n := ArrSize(decls);
  FOR i := 0 TO n - 1 DO
  BEGIN
    item := ArrItem(decls, i);
    nt := NodeType(item);
    IF (nt = 'ProcDecl') OR (nt = 'FuncDecl') THEN
    BEGIN
      body := GetObj(item, 'body');
      IF NodeType(body) = 'Block' THEN
      BEGIN
        nm := GetStr(item, 'name');
        idx := LookupDevRoutine(nm);
        IF idx <> 0 THEN dev_ro_dup[idx] := TRUE
        ELSE IF dev_ro_count < MAX_DEV_ROUTINES THEN
        BEGIN
          dev_ro_count := dev_ro_count + 1;
          dev_ro_name[dev_ro_count] := nm;
          dev_ro_decl[dev_ro_count] := item;
          dev_ro_nparams[dev_ro_count] := ParamNamesOf(item, pnames);
          dev_ro_dup[dev_ro_count] := FALSE;
          dev_ro_cached[dev_ro_count] := FALSE;
          dev_ro_busy[dev_ro_count] := FALSE;
        END;
        RegisterDevRoutines(GetObj(body, 'decls'));
      END;
    END;
  END;
END;

FUNCTION DeviceReadonlySummary(idx: INTEGER32; VAR ro: ParamVarArr): INTEGER32;
{ The formals of dev_ro_decl[idx] proven readonly across analyzable local
  helpers, returning the formal count and filling `ro`. Unknown callees,
  body-less/imported routines, ambiguous names, WITH, and call cycles all
  withhold the fact rather than guess. The result is per-parameter: a helper
  may write one buffer and stay readonly for another. }
VAR
  i, e, n, ncalls, cidx, cn, fi: INTEGER32;
  has_with: BOOLEAN;
  written, escaped, callee_ro: ParamVarArr;
  call_formal, call_argpos: ARRAY [1..MAX_CALL_EDGES] OF INTEGER32;
  call_callee: ARRAY [1..MAX_CALL_EDGES] OF Str255;
BEGIN
  IF dev_ro_cached[idx] THEN
  BEGIN
    FOR i := 1 TO MAX_PARAMS DO ro[i] := dev_ro_mask[idx][i];
    DeviceReadonlySummary := dev_ro_nparams[idx];
  END
  ELSE IF dev_ro_busy[idx] THEN
  BEGIN
    { Cycle: withhold everything, and do not cache -- the enclosing call in
      progress owns the real answer. }
    FOR i := 1 TO MAX_PARAMS DO ro[i] := FALSE;
    DeviceReadonlySummary := dev_ro_nparams[idx];
  END
  ELSE
  BEGIN
    dev_ro_busy[idx] := TRUE;
    ComputeReadonlyEffects(dev_ro_decl[idx]);
    n := eff_nparams;
    has_with := eff_has_with;
    ncalls := eff_ncalls;
    FOR i := 1 TO MAX_PARAMS DO
    BEGIN
      written[i] := eff_written[i];
      escaped[i] := eff_escaped[i];
    END;
    FOR e := 1 TO ncalls DO
    BEGIN
      call_formal[e] := eff_call_formal[e];
      call_callee[e] := eff_call_callee[e];
      call_argpos[e] := eff_call_argpos[e];
    END;
    FOR i := 1 TO MAX_PARAMS DO
      ro[i] := (i <= n) AND (NOT has_with) AND (NOT written[i]) AND (NOT escaped[i]);
    FOR e := 1 TO ncalls DO
    BEGIN
      fi := call_formal[e];
      IF ro[fi] THEN
      BEGIN
        cidx := LookupDevRoutine(call_callee[e]);
        IF cidx = 0 THEN ro[fi] := FALSE
        ELSE IF dev_ro_dup[cidx] THEN ro[fi] := FALSE
        ELSE
        BEGIN
          cn := DeviceReadonlySummary(cidx, callee_ro);
          IF call_argpos[e] >= cn THEN ro[fi] := FALSE
          ELSE IF NOT callee_ro[call_argpos[e] + 1] THEN ro[fi] := FALSE;
        END;
      END;
    END;
    dev_ro_busy[idx] := FALSE;
    dev_ro_cached[idx] := TRUE;
    FOR i := 1 TO MAX_PARAMS DO dev_ro_mask[idx][i] := ro[i];
    DeviceReadonlySummary := n;
  END;
END;

PROCEDURE ApplyKernelParamAttrs(decl, fn: ADRMEM; n: INTEGER32; VAR tks: ParamTkArr);
{ Attach the pointer-parameter facts LLVM cannot infer for a bare device
  pointer: natural alignment, dereferenceable, readonly/nocapture, and (only
  when explicitly opted into) noalias. Called for a real NVPTX kernel entry
  only, so this is inert on the CPU-device parity path. }
VAR
  i, cn: INTEGER32;
  idx: INTEGER32;
  ro: ParamVarArr;
  pointee: INTEGER;
  attr: ADRMEM;
BEGIN
  FOR i := 1 TO MAX_PARAMS DO ro[i] := FALSE;
  idx := 0;
  FOR i := 1 TO dev_ro_count DO
    IF dev_ro_decl[i] = decl THEN idx := i;
  IF idx <> 0 THEN cn := DeviceReadonlySummary(idx, ro);
  FOR i := 1 TO n DO
    IF TypeKind(tks[i]) = TK_POINTER THEN
    BEGIN
      pointee := types[tks[i]].elem_tid;
      { Natural alignment of the pointee: without it the NVPTX backend
        annotates every pointer parameter `.ptr .global .align 1`, though the
        element type is known and genuinely better aligned than that. }
      IF align_kind_id <> 0 THEN
      BEGIN
        attr := LLVMCreateEnumAttribute(ctx, align_kind_id, TypeAlignBytes(pointee));
        LLVMAddAttributeAtIndex(fn, i, attr);
      END;
      { dereferenceable(bytes): only for a statically sized pointee. A SUPER
        ARRAY has no static extent, and nothing ties such a buffer to
        whichever sibling parameter might carry its length, so no size is
        claimed for one. }
      IF (TypeKind(pointee) = TK_ARRAY) AND (NOT types[pointee].is_super) AND (deref_kind_id <> 0) THEN
      BEGIN
        attr := LLVMCreateEnumAttribute(ctx, deref_kind_id, TypeSizeBytes(pointee));
        LLVMAddAttributeAtIndex(fn, i, attr);
      END;
      IF ro[i] THEN
      BEGIN
        IF readonly_kind_id <> 0 THEN
        BEGIN
          attr := LLVMCreateEnumAttribute(ctx, readonly_kind_id, 0);
          LLVMAddAttributeAtIndex(fn, i, attr);
        END;
        IF nocapture_kind_id <> 0 THEN
        BEGIN
          attr := LLVMCreateEnumAttribute(ctx, nocapture_kind_id, 0);
          LLVMAddAttributeAtIndex(fn, i, attr);
        END
        ELSE IF captures_kind_id <> 0 THEN
        BEGIN
          attr := LLVMCreateEnumAttribute(ctx, captures_kind_id, 0); { captures(none) }
          LLVMAddAttributeAtIndex(fn, i, attr);
        END;
      END;
      IF noalias_kernel_params AND (noalias_kind_id <> 0) THEN
      BEGIN
        attr := LLVMCreateEnumAttribute(ctx, noalias_kind_id, 0);
        LLVMAddAttributeAtIndex(fn, i, attr);
      END;
    END;
END;

PROCEDURE CodegenRoutineDecl(decl: ADRMEM; is_func: BOOLEAN);
VAR
  name: Str255;
  params_arr, body_blk: ADRMEM;
  n: INTEGER32;
  names: ParamNameArr;
  tks: ParamTkArr;
  isvar: ParamVarArr;
  needs_copy: ParamVarArr;
  param_llvm_types: ADRMEM;
  i: INTEGER32;
  ret_tk: INTEGER;
  ret_llvm_ty, fnty, fn, entry_bb2: ADRMEM;
  param_val, palloca, ret_load: ADRMEM;
  existing: INTEGER32;
  ridx: INTEGER32;
  has_block_body: BOOLEAN;
  is_c, is_exported_entry, is_vararg: BOOLEAN;
  vararg_flag: INTEGER32;
  agg_llvm_ty, byval_attr, align_attr: ADRMEM;
  llvm_idx, n_llvm: INTEGER32;
  agg_class, n_pieces, eb: INTEGER;
  piece_kind: SysVPieceArr;
  piece_bytes: SysVPieceSzArr;
  cstruct_ty, cptr: ADRMEM;
  ret_class, ret_npieces: INTEGER;
  ret_pk: SysVPieceArr;
  ret_pb: SysVPieceSzArr;
  sret_attr, noalias_attr: ADRMEM;
BEGIN
  name := GetStr(decl, 'name');
  body_blk := GetObj(decl, 'body');
  has_block_body := NodeType(body_blk) = 'Block';
  { IsCForeignDecl(decl) reflects only THIS decl node's own attributes/
    directive -- a FORWARD-declared [C] EXTERN's later real definition (the
    existing<>0 branch below) may not repeat EXTERN/[C] on the body-bearing
    decl, so the routine table's own is_c (set once, at first declaration)
    is the source of truth once ridx is known; see below. }
  is_c := IsCForeignDecl(decl);
  { [VARARGS] only means anything across the C ABI, and (like is_c) the
    routine table's own copy is the source of truth once ridx is known. }
  is_vararg := is_c AND IsVarargsDecl(decl);
  is_exported_entry := GetBool(decl, 'is_exported_entry');

  existing := LookupRoutine(name);
  IF existing <> 0 THEN
  BEGIN
    { A prior FORWARD (or, degenerately, EXTERN) placeholder for this same
      name -- reuse its already-declared LLVM function/type rather than
      calling LLVMAddFunction again (which would just silently uniquify the
      name into a second, wrong function). A second placeholder, or a
      second real definition, for the same name is still an error. }
    IF routines[existing].has_body OR (NOT has_block_body) THEN
      AbortWith2('codegen: duplicate routine declaration: ', name);
    ridx := existing;
    fn := routines[ridx].fn;
    fnty := routines[ridx].fnty;
    ret_tk := routines[ridx].ret_tk;
    { A FORWARD-declared PROCEDURE (not FUNCTION) stores ret_tk as
      TK_UNKNOWN, matching the non-forward branch below -- LLVMTypeForTk has
      no case for TK_UNKNOWN, so it must not be called for a void routine. }
    IF is_func THEN ret_llvm_ty := LLVMTypeForTk(ret_tk)
    ELSE ret_llvm_ty := voidty;
    n := routines[ridx].nparams;
    FOR i := 1 TO n DO
    BEGIN
      tks[i] := routines[ridx].param_tk[i];
      isvar[i] := routines[ridx].param_is_var[i];
      needs_copy[i] := routines[ridx].param_needs_copy[i];
    END;
    params_arr := GetObj(decl, 'params');
    FlattenParams(params_arr, n, names, tks, isvar, needs_copy);
    routines[ridx].has_body := TRUE;
    is_c := routines[ridx].is_c; { source of truth once ridx is known -- see note above }
    is_vararg := routines[ridx].is_vararg; { likewise }
    { The already-built fnty is reused verbatim here, so it must already
      reflect the same classification recomputed below -- true as long as
      the placeholder that first declared this name (the fresh-declaration
      ELSE branch, whether reached as a genuine FORWARD or as this same
      branch's own first pass) applied the identical is_func/ret_tk-driven
      classification, which it always does; ClassifyAggregate/FuncRetAggClass
      are pure functions of ret_tk, so declaration and reuse can never
      disagree (same idiom as the parameter side). A plain-Pascal FUNCTION
      forward-declared through a spliced INTERFACE UNIT (e.g. jsonutil's
      Str255-returning routines) legitimately reaches this path with an
      aggregate return and a real body -- that is the normal case, not an
      error. A [C] EXTERN aggregate-returning FUNCTION reaching here is
      different: EXTERN promises the body lives elsewhere, so a real body
      under the same name is a self-contradictory program, not a shape this
      compiler can lower -- refuse it loudly rather than emit a body against
      an EXTERN declaration. }
    ret_class := 0;
    IF is_func THEN
      IF IsAggregateTk(ret_tk) THEN
      BEGIN
        IF has_block_body AND is_c THEN
          AbortWith2('codegen: [C] EXTERN routine with an aggregate return cannot be defined here: ', name)
        ELSE
        BEGIN
          ClassifyAggregate(ret_tk, ret_class, ret_npieces, ret_pk, ret_pb);
          IF ret_class = SYSV_CLASS_MEMORY THEN ret_llvm_ty := voidty
          ELSE ret_llvm_ty := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
        END;
      END;
  END
  ELSE
  BEGIN
    params_arr := GetObj(decl, 'params');
    FlattenParams(params_arr, n, names, tks, isvar, needs_copy);

    IF is_func THEN
    BEGIN
      ret_tk := ResolveTypeExpr(GetObj(decl, 'return_type'));
      ret_llvm_ty := LLVMTypeForTk(ret_tk);
    END
    ELSE
    BEGIN
      ret_tk := TK_UNKNOWN;
      ret_llvm_ty := voidty;
    END;

    { The return has to be classified BEFORE the parameter list is built: a
      FUNCTION (plain Pascal or [C] FOREIGN alike) returning a MEMORY-class
      aggregate returns void and takes a hidden pointer to the caller's
      result storage as its FIRST LLVM parameter, shifting every real
      parameter's LLVM index by one. A COERCED-class aggregate return needs
      no hidden pointer -- it comes back in one or two registers, i.e. as a
      plain non-aggregate LLVM return type -- so it only rewrites
      ret_llvm_ty. Everything else (PROCEDUREs and scalar returns) is
      untouched. }
    ret_class := 0;
    IF is_func THEN
      IF IsAggregateTk(ret_tk) THEN
      BEGIN
        ClassifyAggregate(ret_tk, ret_class, ret_npieces, ret_pk, ret_pb);
        IF ret_class = SYSV_CLASS_MEMORY THEN ret_llvm_ty := voidty
        ELSE ret_llvm_ty := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
      END;

    { A COERCED-class [C] aggregate parameter is passed as one LLVM
      parameter per eightbyte (at most two), so the LLVM parameter list can
      be longer than the Pascal one -- llvm_idx below is the running LLVM
      parameter index, and n_llvm the final count. Two slots per Pascal
      parameter is the worst case, plus one for an sret hidden pointer
      (which also seeds llvm_idx at 1 instead of 0). }
    param_llvm_types := AllocPtrArray(n * 2 + 1);
    llvm_idx := 0;
    IF ret_class = SYSV_CLASS_MEMORY THEN
    BEGIN
      SetPtrArrayElem(param_llvm_types, 0, LLVMPointerType(LLVMTypeForTk(ret_tk), 0));
      llvm_idx := 1;
    END;
    FOR i := 1 TO n DO
    BEGIN
      IF isvar[i] THEN
      BEGIN
        SetPtrArrayElem(param_llvm_types, llvm_idx, LLVMPointerType(LLVMTypeForTk(tks[i]), 0));
        llvm_idx := llvm_idx + 1;
      END
      ELSE IF needs_copy[i] THEN
      BEGIN
        { Value-mode aggregate param (ARRAY/RECORD/LSTRING/STRING), plain
          Pascal and [C] FOREIGN alike -- explicit SysV classification,
          matching c_abi.py: MEMORY class (>16 bytes, or 0) is a pointer to
          a private per-call copy, with the byval(ty)/align attributes
          attached below once `fn` exists; COERCED class (<=16 bytes, all
          eightbytes INTEGER/SSE) is flattened into its register pieces
          instead, and gets no parameter attribute at all. }
        ClassifyAggregate(tks[i], agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
        BEGIN
          SetPtrArrayElem(param_llvm_types, llvm_idx, LLVMPointerType(LLVMTypeForTk(tks[i]), 0));
          llvm_idx := llvm_idx + 1;
        END
        ELSE
          FOR eb := 1 TO n_pieces DO
          BEGIN
            SetPtrArrayElem(param_llvm_types, llvm_idx,
                            SysVPieceLLVMType(piece_kind[eb], piece_bytes[eb]));
            llvm_idx := llvm_idx + 1;
          END;
      END
      ELSE
      BEGIN
        SetPtrArrayElem(param_llvm_types, llvm_idx, LLVMTypeForTk(tks[i]));
        llvm_idx := llvm_idx + 1;
      END;
    END;
    n_llvm := llvm_idx;

    { A handful of C runtime/libm functions (malloc, free, printf, ...) are
      already declared in the module by the init block above, for this
      compiler's OWN internal codegen (NEW/DISPOSE, WRITE/WRITELN, string
      builtins, SQRT/SIN/...) to call directly via their fn/fnty globals --
      independently of whatever the source program's own [C]; EXTERN
      declares under the same name (e.g. jsonutil.pas/lexer.pas both declare
      `EXTERN malloc` for their own use). Reuse that existing LLVM function
      instead of calling LLVMAddFunction again: a second LLVMAddFunction for
      an already-declared name doesn't error, it silently uniquifies to
      `malloc.1`/`free.2`/etc, which then has no real symbol to link against
      -- found only by actually clang-linking self-hosted output, since
      LLVMVerifyModule accepts the (internally consistent, if wrong) IR. }
    IF name = 'malloc' THEN BEGIN fn := malloc_fn; fnty := malloc_fnty; END
    ELSE IF name = 'free' THEN BEGIN fn := free_fn; fnty := free_fnty; END
    ELSE IF name = 'memmove' THEN BEGIN fn := memmove_fn; fnty := memmove_fnty; END
    ELSE IF name = 'memcmp' THEN BEGIN fn := memcmp_fn; fnty := memcmp_fnty; END
    ELSE IF name = 'positn' THEN BEGIN fn := positn_fn; fnty := positn_fnty; END
    ELSE IF name = 'scaneq' THEN BEGIN fn := scaneq_fn; fnty := scaneq_fnty; END
    ELSE IF name = 'scanne' THEN BEGIN fn := scanne_fn; fnty := scanne_fnty; END
    ELSE IF name = 'encode_value' THEN BEGIN fn := encode_fn; fnty := encode_fnty; END
    ELSE IF name = 'decode_value' THEN BEGIN fn := decode_fn; fnty := decode_fnty; END
    ELSE IF name = 'sqrt' THEN BEGIN fn := sqrt_fn; fnty := sqrt_fnty; END
    ELSE IF name = 'sin' THEN BEGIN fn := sin_fn; fnty := sin_fnty; END
    ELSE IF name = 'cos' THEN BEGIN fn := cos_fn; fnty := cos_fnty; END
    ELSE IF name = 'log' THEN BEGIN fn := log_fn; fnty := log_fnty; END
    ELSE IF name = 'exp' THEN BEGIN fn := exp_fn; fnty := exp_fnty; END
    ELSE IF name = 'atan' THEN BEGIN fn := atan_fn; fnty := atan_fnty; END
    ELSE IF name = 'printf' THEN BEGIN fn := printf_fn; fnty := printf_fnty; END
    ELSE
    BEGIN
      { A [VARARGS] [C] routine gets a genuinely variadic LLVM function type
        (trailing is_var_arg = 1), the same shape the printf/write_fmt
        declarations in the init block above already use. }
      IF is_vararg THEN vararg_flag := 1 ELSE vararg_flag := 0;
      fnty := LLVMFunctionType(ret_llvm_ty, param_llvm_types, n_llvm, vararg_flag);
      fn := LLVMAddFunction(modl, MakeCStr(name), fnty);
    END;

    { Reusing an init-declared function means the LLVM signature that call
      sites must satisfy is the init block's, not the source declaration's.
      Where the two disagree the recorded parameter types have to follow the
      real function, or CoerceForAssign marshals every actual to the source
      width and LLVM rejects the call. `malloc(size: CINT)` is the live case:
      the init block declares C's size_t (i64) on this LP64 host, while every
      self-hosting source spells the parameter CINT (i32). }
    IF (name = 'malloc') AND (n = 1) THEN tks[1] := TK_INTEGER64;

    { Register the routine before codegen'ing its body -- direct
      self-recursion (Fact calling Fact) needs the routine table entry to
      already exist when the body's own FuncCall/ProcCallStmt nodes resolve
      it. Mutual recursion (A calls B declared later) is out of scope, same
      as it would be without a FORWARD declaration in standard Pascal. }
    IF nroutines >= MAX_ROUTINES THEN AbortWith('codegen: too many routines');
    nroutines := nroutines + 1;
    ridx := nroutines;
    routines[ridx].name := name;
    routines[ridx].is_func := is_func;
    routines[ridx].fn := fn;
    routines[ridx].fnty := fnty;
    routines[ridx].ret_tk := ret_tk;
    routines[ridx].nparams := n;
    FOR i := 1 TO n DO
    BEGIN
      routines[ridx].param_tk[i] := tks[i];
      routines[ridx].param_is_var[i] := isvar[i];
      routines[ridx].param_needs_copy[i] := needs_copy[i];
    END;
    routines[ridx].has_body := has_block_body;
    routines[ridx].is_c := is_c;
    routines[ridx].is_vararg := is_vararg;

    { Attach byval(ty)/align (and sret(ty)/noalias/align for a MEMORY-class
      return) at the DECLARATION side too (not just the call site below) --
      LLVM attaches parameter attributes to both the function
      definition/declaration and each call site; clang emits both, and only
      doing one leaves the IR inconsistent with what a real C compiler
      produces for the same signature (verification step 7). Applies to
      plain-Pascal routines exactly like [C] FOREIGN ones, via the same
      FuncRetAggClass/ClassifyAggregate calls both sides use. Attribute
      index is 1-based over LLVM parameters (0 is the return), which is why
      it is walked with llvm_idx rather than the Pascal
      parameter index: a COERCED aggregate parameter occupies one slot per
      eightbyte and carries no attribute of its own -- byval and align
      describe a pointer to memory, which a register-passed aggregate never
      has. }
    llvm_idx := 0;
    IF ret_class = SYSV_CLASS_MEMORY THEN
    BEGIN
      { The hidden result pointer is LLVM parameter 0, i.e. attribute
        index 1. `sret(ty)` names the pointee type the callee writes the
        result through; `noalias` is the SysV promise that this storage is
        the caller's fresh result temp and overlaps nothing else the call
        can see; `align` matches what the byval path attaches, and what
        the reference records alongside its own sret attributes. }
      agg_llvm_ty := LLVMTypeForTk(ret_tk);
      sret_attr := LLVMCreateTypeAttribute(ctx, sret_kind_id, agg_llvm_ty);
      align_attr := LLVMCreateEnumAttribute(ctx, align_kind_id, SysVByvalAlign(ret_tk));
      LLVMAddAttributeAtIndex(fn, 1, sret_attr);
      LLVMAddAttributeAtIndex(fn, 1, align_attr);
      IF noalias_kind_id <> 0 THEN
      BEGIN
        noalias_attr := LLVMCreateEnumAttribute(ctx, noalias_kind_id, 0);
        LLVMAddAttributeAtIndex(fn, 1, noalias_attr);
      END;
      llvm_idx := 1;
    END;
    FOR i := 1 TO n DO
    BEGIN
      IF needs_copy[i] THEN
      BEGIN
        ClassifyAggregate(tks[i], agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
        BEGIN
          agg_llvm_ty := LLVMTypeForTk(tks[i]);
          byval_attr := LLVMCreateTypeAttribute(ctx, byval_kind_id, agg_llvm_ty);
          align_attr := LLVMCreateEnumAttribute(ctx, align_kind_id, SysVByvalAlign(tks[i]));
          LLVMAddAttributeAtIndex(fn, llvm_idx + 1, byval_attr);
          LLVMAddAttributeAtIndex(fn, llvm_idx + 1, align_attr);
          llvm_idx := llvm_idx + 1;
        END
        ELSE
          llvm_idx := llvm_idx + n_pieces;
      END
      ELSE
        llvm_idx := llvm_idx + 1;
    END;
  END;

  { An exported DEVICE PROCEDURE becomes a launchable NVPTX entry. The
    interface placeholder has no flag; the implementation declaration does. }
  IF is_nvptx_device AND is_exported_entry THEN
  BEGIN
    LLVMSetFunctionCallConv(fn, 71); { LLVMCCallConv::PTX_Kernel }
    ApplyKernelParamAttrs(decl, fn, n, tks);
    ApplyLaunchBoundAttrs(decl, fn);
  END;

  { EXTERN/FORWARD placeholder: the function is declared (or was already,
    on a prior FORWARD pass) and registered, but there is no Block body to
    codegen yet -- nothing further to do until (if ever) a real definition
    for this same name arrives. Wrapped in an IF rather than a bare EXIT,
    matching CodegenBinOp's own note: this dialect has no EXIT
    statement/procedure at all, so an early return has to be an IF guard. }
  IF has_block_body THEN
  BEGIN
    entry_bb2 := LLVMAppendBasicBlockInContext(ctx, fn, MakeCStr('entry'));
    LLVMPositionBuilderAtEnd(builder, entry_bb2);
    cur_fn := fn;
    PushScope;
    in_local_scope := TRUE;

    IF is_func THEN
    BEGIN
      cur_func_name := name;
      cur_func_ret_tk := ret_tk;
      IF ret_class = SYSV_CLASS_MEMORY THEN
        { The hidden sret pointer (LLVM parameter 0) already points at the
          caller's own result storage -- use it directly, exactly like a
          byval parameter uses its incoming pointer directly, so every
          RETURN/function-name-assignment site (which always addresses
          cur_func_ret_slot via cur_func_ret_tk, the real Pascal type, not
          ret_llvm_ty) stores straight into the caller's buffer with no
          extra copy, and the epilogue below needs no load/ret of the LLVM
          return type at all (which is void here). }
        cur_func_ret_slot := LLVMGetParam(fn, 0)
      ELSE IF ret_class = SYSV_CLASS_COERCED THEN
      BEGIN
        { Real aggregate-typed storage, over-aligned to a full eightbyte so
          the epilogue's coerced-type reload can view it as the (possibly
          wider) coerced register layout -- mirrors the COERCED parameter
          prologue's own over-aligned slot. }
        cur_func_ret_slot := EntryAlloca(LLVMTypeForTk(ret_tk), 'return_value');
        LLVMSetAlignment(cur_func_ret_slot, 8);
      END
      ELSE
        cur_func_ret_slot := EntryAlloca(ret_llvm_ty, 'return_value');
      IF (ret_tk = TK_REAL) OR (ret_tk = TK_REAL32) THEN LLVMBuildStore(builder, LLVMConstReal(LLVMTypeForTk(ret_tk), 0.0), cur_func_ret_slot)
      ELSE IF (ret_tk = TK_BOOLEAN) OR (ret_tk = TK_CHAR) OR IsIntegerFamilyTk(ret_tk) THEN
        LLVMBuildStore(builder, LLVMConstInt(LLVMTypeForTk(ret_tk), 0, 0), cur_func_ret_slot)
      ELSE
        { ADRMEM/POINTER, or an aggregate (LSTRING/STRING/ARRAY/RECORD)
          return type -- neither fits LLVMConstInt (not an integer LLVM
          type), so zero it via LLVMConstNull instead, matching the
          reference's own all-zero default-return initialization. Typed by
          the real Pascal return type (cur_func_ret_slot's own storage
          type), not ret_llvm_ty, which for a MEMORY/COERCED aggregate
          return no longer matches that storage's type. }
        LLVMBuildStore(builder, LLVMConstNull(LLVMTypeForTk(ret_tk)), cur_func_ret_slot);
    END
    ELSE
      cur_func_name := '';

    { llvm_idx is the running LLVM parameter index: it starts at 1 instead
      of 0 when a hidden sret result pointer occupies LLVM parameter 0 (see
      the matching seed in the signature-building and attribute-attachment
      code above), and from there only tracks the Pascal parameter index
      while no COERCED aggregate parameter has been seen, since such a
      parameter arrives as one LLVM parameter per eightbyte (at most two). }
    IF ret_class = SYSV_CLASS_MEMORY THEN llvm_idx := 1 ELSE llvm_idx := 0;
    FOR i := 1 TO n DO
    BEGIN
      param_val := LLVMGetParam(fn, llvm_idx);
      llvm_idx := llvm_idx + 1;
      IF isvar[i] THEN
        palloca := param_val { the incoming pointer already IS the storage }
      ELSE IF needs_copy[i] THEN
      BEGIN
        { Value-mode aggregate param, plain Pascal and [C] FOREIGN alike. }
        ClassifyAggregate(tks[i], agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
          { SysV byval: the incoming pointer already refers to a private
            per-call copy the caller made (see the byval caller-side temp in
            CodegenCallCommon) -- use it directly as storage, exactly like
            isvar above, no further copy needed. }
          palloca := param_val
        ELSE
        BEGIN
          { COERCED class: the aggregate arrived in one or two registers.
            Reverse the caller's flattening -- give it real storage of the
            aggregate's own type and write each incoming piece back through
            the coerced piece struct laid over that storage, so the rest of
            codegen sees an ordinary aggregate local. The slot is
            over-aligned to a full eightbyte so every piece store is
            naturally aligned even when the aggregate's own alignment is
            smaller (e.g. a two-INTEGER32 record, align 4, written as one
            i64). }
          palloca := EntryAlloca(LLVMTypeForTk(tks[i]), names[i]);
          LLVMSetAlignment(palloca, 8);
          cstruct_ty := SysVCoercedStructType(n_pieces, piece_kind, piece_bytes);
          cptr := LLVMBuildBitCast(builder, palloca, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
          FOR eb := 1 TO n_pieces DO
          BEGIN
            { param_val already holds the first piece; the rest follow it
              in consecutive LLVM parameters. }
            IF eb > 1 THEN
            BEGIN
              param_val := LLVMGetParam(fn, llvm_idx);
              llvm_idx := llvm_idx + 1;
            END;
            LLVMBuildStore(builder, param_val, SysVCoercedPiecePtr(cptr, cstruct_ty, eb));
          END;
        END;
      END
      ELSE
      BEGIN
        palloca := EntryAlloca(LLVMTypeForTk(tks[i]), names[i]);
        LLVMBuildStore(builder, param_val, palloca);
      END;
      IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
      nsymbols := nsymbols + 1;
      symbols[nsymbols].name := names[i];
      symbols[nsymbols].tk := tks[i];
      symbols[nsymbols].llvm_val := palloca;
    END;

    CodegenDeclList(GetObj(body_blk, 'decls'));
    SetupFunctionLabels(GetObj(body_blk, 'body'));
    CodegenStmtArray(GetObj(body_blk, 'body'));

    IF is_func THEN
    BEGIN
      IF ret_class = SYSV_CLASS_MEMORY THEN
        { Every RETURN/function-name-assignment already stored straight
          into the caller's sret buffer (cur_func_ret_slot IS that pointer)
          -- nothing left to load, and this function's LLVM return type is
          void. }
        LLVMBuildRetVoid(builder)
      ELSE IF ret_class = SYSV_CLASS_COERCED THEN
      BEGIN
        { Reverse of the COERCED parameter prologue: view the (over-aligned)
          aggregate storage as the coerced register layout and read that
          layout back out as one value, ready to `ret` in one or two
          registers -- mirrors the caller side's own coerced-return
          reconstruction (CodegenCallCommon) in the opposite direction. }
        cstruct_ty := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
        cptr := LLVMBuildBitCast(builder, cur_func_ret_slot, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
        ret_load := LLVMBuildLoad2(builder, cstruct_ty, cptr, MakeCStr(''));
        LLVMSetAlignment(ret_load, 8);
        ret_load := LLVMBuildRet(builder, ret_load);
      END
      ELSE
      BEGIN
        ret_load := LLVMBuildLoad2(builder, ret_llvm_ty, cur_func_ret_slot, MakeCStr(''));
        ret_load := LLVMBuildRet(builder, ret_load);
      END;
    END
    ELSE
      LLVMBuildRetVoid(builder);

    PopScope;
    in_local_scope := FALSE;
    cur_func_name := '';
    cur_fn := main_fn;
    LLVMPositionBuilderAtEnd(builder, entry_bb);
  END;
END;

PROCEDURE CodegenTypeDecl(decl: ADRMEM);
VAR
  name: Str255;
  tid: INTEGER;
BEGIN
  name := GetStr(decl, 'name');
  IF LookupNamedType(name) <> 0 THEN
    AbortWith2('codegen: duplicate type declaration: ', name);
  tid := ResolveTypeExpr(GetObj(decl, 'type_expr'));
  IF tid < 5 THEN
    AbortWith2('codegen: TYPE cannot alias a bare scalar name: ', name);
  types[tid].name := name;
END;

PROCEDURE CodegenConstDecl(decl: ADRMEM);
{ Every CONST this file's own native sources declare is a plain (optionally
  MINUS-negated) integer or REAL literal -- this compile-time-folds and
  remembers the value in `const_tbl`, mirroring the Python reference's
  eval_const_expr/self.constants side table rather than emitting a real LLVM
  global. }
VAR
  name: Str255;
  val_node: ADRMEM;
BEGIN
  name := GetStr(decl, 'name');
  IF LookupConst(name) <> 0 THEN
    AbortWith2('codegen: duplicate const declaration: ', name);
  val_node := GetObj(decl, 'value');
  nconsts := nconsts + 1;
  const_tbl[nconsts].name := name;
  IF NodeType(val_node) = 'RealLiteral' THEN
  BEGIN
    const_tbl[nconsts].is_real := TRUE;
    const_tbl[nconsts].rval := GetReal(val_node, 'value');
  END
  ELSE IF (NodeType(val_node) = 'UnaryOp') AND (GetStr(val_node, 'op') = 'MINUS')
      AND (NodeType(GetObj(val_node, 'operand')) = 'RealLiteral') THEN
  BEGIN
    const_tbl[nconsts].is_real := TRUE;
    const_tbl[nconsts].rval := 0.0 - GetReal(GetObj(val_node, 'operand'), 'value');
  END
  ELSE
  BEGIN
    const_tbl[nconsts].is_real := FALSE;
    const_tbl[nconsts].ival := IntLiteralValue(val_node);
  END;
END;

PROCEDURE CodegenDecl(decl: ADRMEM);
VAR
  nt: Str255;
BEGIN
  nt := NodeType(decl);
  IF nt = 'VarDecl' THEN CodegenVarDecl(decl)
  ELSE IF nt = 'TypeDecl' THEN CodegenTypeDecl(decl)
  ELSE IF nt = 'ConstDecl' THEN CodegenConstDecl(decl)
  ELSE IF nt = 'ProcDecl' THEN CodegenRoutineDecl(decl, FALSE)
  ELSE IF nt = 'FuncDecl' THEN CodegenRoutineDecl(decl, TRUE)
  ELSE IF nt = 'LabelDecl' THEN
    { No-op: every label's block was already allocated by SetupFunctionLabels
      from the actual LabelStmt occurrences in the body, independent of this
      declaration's text -- matches the Python reference's own LabelDecl
      handling (codegen/decls.py: emits no direct code). }
    BEGIN END
  ELSE
    AbortWith2('codegen: unhandled declaration kind: ', nt);
END;

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

BEGIN
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
      x86-64 SysV layout assumptions. }
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
