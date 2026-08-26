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

FUNCTION LoadFileFcbPtr(name: Str255): ADRMEM;
{ Loads a FILE variable's opaque i8* handle and bitcasts it to filefcbty* --
  every RESET/REWRITE/GET/PUT/CLOSE/DISCARD/ASSIGN/EOF/EOLN call site's
  first step. }
VAR
  symi: INTEGER32;
  handle: ADRMEM;
BEGIN
  symi := LookupSym(name);
  IF symi = 0 THEN AbortWith2('codegen: undefined variable: ', name);
  IF TypeKind(symbols[symi].tk) <> TK_FILE THEN
    AbortWith2('codegen: not a FILE variable: ', name);
  handle := LLVMBuildLoad2(builder, i8ptrty, symbols[symi].llvm_val, MakeCStr(''));
  LoadFileFcbPtr := LLVMBuildBitCast(builder, handle, LLVMPointerType(filefcbty, 0), MakeCStr(''));
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

{ ============================== statements ================================ }

PROCEDURE CodegenStmt(stmt: ADRMEM); FORWARD;

{ --------------------------- GOTO / labels --------------------------------
  Mirrors the Python reference's _collect_labels/setup_function_labels: every
  LabelStmt reachable within a routine gets one LLVM basic block, allocated
  up front (before the body is codegen'd) so a forward GOTO can branch to a
  block that doesn't exist yet in program-text order. Routine-local only --
  the `labels` table is rebuilt from scratch for every PROGRAM/PROCEDURE/
  FUNCTION/unit-init body (see SetupFunctionLabels's call sites), matching
  the reference's own per-routine label_blocks and its "GOTO to undefined
  label" restriction against cross-routine jumps. }

FUNCTION IntToStr255(n: INTEGER32): Str255;
{ No such helper exists anywhere else in this file -- every other numeric
  diagnostic is either a fixed string or routed through AbortWith2's plain
  Str255 concatenation, never a formatted integer. Needed here because a
  numeric GOTO label (e.g. `GOTO 100;`) arrives from the parser as a JSON
  number, not a string, and the `labels` table's lookup key is always text.
  Builds digits into `tmp` least-significant-first via direct Str255
  indexing (the same s[0]=length-byte convention CStrToStr255 uses), then
  reverses into `res` -- no CONCAT needed, this is plain char-array work. }
VAR
  neg: BOOLEAN;
  v: INTEGER32;
  digit: INTEGER32;
  tmp, res: Str255;
  len, i, out_i: INTEGER;
BEGIN
  neg := n < 0;
  IF neg THEN v := -n ELSE v := n;
  len := 0;
  IF v = 0 THEN
  BEGIN
    len := 1;
    tmp[1] := '0';
  END
  ELSE
    WHILE v > 0 DO
    BEGIN
      len := len + 1;
      digit := ORD('0') + (v MOD 10);
      tmp[len] := CHR(RETYPE(INTEGER, digit));
      v := v DIV 10;
    END;
  out_i := 0;
  IF neg THEN
  BEGIN
    out_i := out_i + 1;
    res[out_i] := '-';
  END;
  FOR i := len DOWNTO 1 DO
  BEGIN
    out_i := out_i + 1;
    res[out_i] := tmp[i];
  END;
  res[0] := CHR(out_i);
  IntToStr255 := res;
END;

FUNCTION LabelKey(node: ADRMEM; key: Str255): Str255;
{ The parser's 'label' field (GotoStmt/LabelStmt/BreakStmt/CycleStmt) is a
  JSON number for a numeric label, a JSON string for an identifier label --
  read whichever is present and normalize to the same Str255 key either way. }
VAR
  item: ADRMEM;
BEGIN
  item := GetObj(node, key);
  IF (item <> NIL) AND (cJSON_IsNumber(item) <> 0) THEN
    LabelKey := IntToStr255(GetInt(node, key))
  ELSE
    LabelKey := GetStr(node, key);
END;

FUNCTION LookupLabel(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := nlabels;
  WHILE (i >= 1) AND (labels[i].name <> name) DO
    i := i - 1;
  LookupLabel := i;
END;

PROCEDURE RegisterLabel(name: Str255);
BEGIN
  IF LookupLabel(name) = 0 THEN
  BEGIN
    IF nlabels >= MAX_LABELS THEN AbortWith('codegen: too many labels in one routine');
    nlabels := nlabels + 1;
    labels[nlabels].name := name;
    labels[nlabels].block := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('label_'));
  END;
END;

PROCEDURE CollectLabels(stmt: ADRMEM); FORWARD;

PROCEDURE CollectLabelsArr(arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  IF arr <> NIL THEN
  BEGIN
    n := ArrSize(arr);
    FOR i := 0 TO n - 1 DO
      CollectLabels(ArrItem(arr, i));
  END;
END;

PROCEDURE CollectLabels(stmt: ADRMEM);
{ Non-emitting walk mirroring the reference's own _collect_labels node
  coverage: every statement kind that can syntactically contain a LabelStmt
  (directly or nested) is walked; leaf statement kinds (assignment, ProcCall,
  RETURN/BREAK/CYCLE, GOTO itself) have no children and are ignored. This
  dialect has no EXIT statement (see CodegenBinOp's own note on the same
  restriction), so an early "stmt = NIL" return is instead the outermost
  guard around the whole dispatch chain. }
VAR
  nt: Str255;
  elements, el: ADRMEM;
  n, i: INTEGER32;
BEGIN
  IF stmt <> NIL THEN
  BEGIN
  nt := NodeType(stmt);
  IF nt = 'CompoundStmt' THEN
    CollectLabelsArr(GetObj(stmt, 'stmts'))
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    CollectLabels(GetObj(stmt, 'then_branch'));
    CollectLabels(GetObjOrNil(stmt, 'else_branch'));
  END
  ELSE IF nt = 'WhileStmt' THEN
    CollectLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'RepeatStmt' THEN
    CollectLabelsArr(GetObj(stmt, 'body'))
  ELSE IF nt = 'ForStmt' THEN
    CollectLabels(GetObj(stmt, 'body'))
  ELSE IF nt = 'CaseStmt' THEN
  BEGIN
    elements := GetObj(stmt, 'elements');
    n := ArrSize(elements);
    FOR i := 0 TO n - 1 DO
    BEGIN
      el := ArrItem(elements, i);
      CollectLabels(GetObj(el, 'stmt'));
    END;
    CollectLabels(GetObjOrNil(stmt, 'otherwise'));
  END
  ELSE IF nt = 'LabelStmt' THEN
  BEGIN
    RegisterLabel(LabelKey(stmt, 'label'));
    CollectLabels(GetObj(stmt, 'stmt'));
  END;
  END;
END;

PROCEDURE SetupFunctionLabels(body_arr: ADRMEM);
BEGIN
  nlabels := 0;
  CollectLabelsArr(body_arr);
  cur_routine_has_labels := nlabels > 0;
  pending_loop_label := '';
END;

PROCEDURE CodegenStmtArray(arr: ADRMEM);
VAR
  n, i: INTEGER32;
  dead_bb: ADRMEM;
BEGIN
  n := ArrSize(arr);
  FOR i := 0 TO n - 1 DO
  BEGIN
    { A RETURN/BREAK/CYCLE/GOTO terminates its block; ordinarily nothing
      downstream in a straight-line statement list can still be reached, so
      stop emitting (matches the pre-GOTO behavior exactly when the routine
      has no labels at all). But when it does, a later statement might be a
      LabelStmt (or contain one) that a GOTO elsewhere in the routine
      branches to -- SetupFunctionLabels already gave it a real block, so
      dropping it here would leave that block never populated. Mirrors the
      reference's own codegen_stmt_list: open a fresh (currently
      unreachable) continuation block and keep going instead of stopping. }
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) <> NIL THEN
    BEGIN
      IF NOT cur_routine_has_labels THEN BREAK;
      dead_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('dead'));
      LLVMPositionBuilderAtEnd(builder, dead_bb);
    END;
    CodegenStmt(ArrItem(arr, i));
  END;
END;

PROCEDURE CodegenAssignStmt(stmt: ADRMEM);
VAR
  target, sel: ADRMEM;
  nm: Str255;
  symi: INTEGER32;
  v, addr: ADRMEM;
  target_tid: INTEGER;
BEGIN
  target := GetObj(stmt, 'target');
  IF NodeType(target) <> 'Designator' THEN
    AbortWith('codegen: unsupported assignment target');
  sel := GetObj(target, 'selectors');
  nm := GetStr(target, 'name');

  IF (ArrSize(sel) = 0) AND (cur_func_name <> '') AND (nm = cur_func_name) THEN
  BEGIN
    { `FuncName := expr` inside FuncName's own body assigns through the
      return-value slot, not a symbol -- see cur_func_name's declaration. }
    IF (TypeKind(cur_func_ret_tk) = TK_LSTRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenLStringLiteralAssign(cur_func_ret_slot, cur_func_ret_tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE IF (TypeKind(cur_func_ret_tk) = TK_STRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenStringLiteralAssign(cur_func_ret_slot, cur_func_ret_tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE
    BEGIN
      v := CodegenExpr(GetObj(stmt, 'expr'));
      v := CoerceForAssign(v, last_val_tk, cur_func_ret_tk, GetObj(stmt, 'expr'), nm);
      LLVMBuildStore(builder, v, cur_func_ret_slot);
    END;
  END
  ELSE IF ArrSize(sel) = 0 THEN
  BEGIN
    symi := LookupSym(nm);
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', nm);
    IF (TypeKind(symbols[symi].tk) = TK_LSTRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenLStringLiteralAssign(symbols[symi].llvm_val, symbols[symi].tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE IF (TypeKind(symbols[symi].tk) = TK_STRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenStringLiteralAssign(symbols[symi].llvm_val, symbols[symi].tk,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE
    BEGIN
      v := CodegenExpr(GetObj(stmt, 'expr'));
      v := CoerceForAssign(v, last_val_tk, symbols[symi].tk, GetObj(stmt, 'expr'), nm);
      LLVMBuildStore(builder, v, symbols[symi].llvm_val);
    END;
  END
  ELSE
  BEGIN
    addr := ComputeDesignatorAddress(target);
    target_tid := last_val_tk;
    IF (TypeKind(target_tid) = TK_LSTRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenLStringLiteralAssign(addr, target_tid,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE IF (TypeKind(target_tid) = TK_STRING) AND (NodeType(GetObj(stmt, 'expr')) = 'StringLiteral') THEN
      CodegenStringLiteralAssign(addr, target_tid,
        DecodeStringLiteral(GetStr(GetObj(stmt, 'expr'), 'value')))
    ELSE
    BEGIN
      v := CodegenExpr(GetObj(stmt, 'expr'));
      v := CoerceForAssign(v, last_val_tk, target_tid, GetObj(stmt, 'expr'), nm);
      LLVMBuildStore(builder, v, addr);
    END;
  END;
END;

PROCEDURE CodegenIfStmt(stmt: ADRMEM);
VAR
  cond_val: ADRMEM;
  then_bb, else_bb, end_bb: ADRMEM;
  else_branch: ADRMEM;
BEGIN
  cond_val := CodegenExpr(GetObj(stmt, 'cond'));
  IF last_val_tk <> TK_BOOLEAN THEN
    AbortWith('codegen: IF condition must be BOOLEAN');

  then_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('if_then'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('if_end'));
  else_branch := GetObjOrNil(stmt, 'else_branch');
  IF else_branch <> NIL THEN
    else_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('if_else'))
  ELSE
    else_bb := end_bb;

  LLVMBuildCondBr(builder, cond_val, then_bb, else_bb);

  LLVMPositionBuilderAtEnd(builder, then_bb);
  CodegenStmt(GetObj(stmt, 'then_branch'));
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
    LLVMBuildBr(builder, end_bb);

  IF else_branch <> NIL THEN
  BEGIN
    LLVMPositionBuilderAtEnd(builder, else_bb);
    CodegenStmt(else_branch);
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
      LLVMBuildBr(builder, end_bb);
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenCaseStmt(stmt: ADRMEM);
{ Lowered as a sequential chain of test/body block pairs (like a chain of
  IFs), not a jump table -- simplicity over the optimization the Python
  reference doesn't attempt either at this level (llvmlite's own -O passes
  are what would turn either shape into a real jump table). Scoped to an
  INTEGER selector: a CHAR-keyed CASE is not yet supported, consistent with
  CodegenBinOp's relational operators also only covering INTEGER/REAL. }
VAR
  case_val: ADRMEM;
  case_tk: INTEGER;
  elements, el, constants, c: ADRMEM;
  n, i, nc, ci: INTEGER32;
  end_bb, cur_test_bb, next_test_bb, body_bb: ADRMEM;
  otherwise_stmt: ADRMEM;
  cond_val, one_cond, cval: ADRMEM;
BEGIN
  case_val := CodegenExpr(GetObj(stmt, 'expr'));
  case_tk := last_val_tk;
  IF case_tk <> TK_INTEGER THEN
    AbortWith('codegen: CASE selector must be INTEGER (CHAR-keyed CASE is not yet supported)');

  elements := GetObj(stmt, 'elements');
  n := ArrSize(elements);
  otherwise_stmt := GetObjOrNil(stmt, 'otherwise');
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_end'));

  cur_test_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_test'));
  LLVMBuildBr(builder, cur_test_bb);

  FOR i := 0 TO n - 1 DO
  BEGIN
    LLVMPositionBuilderAtEnd(builder, cur_test_bb);
    el := ArrItem(elements, i);
    constants := GetObj(el, 'constants');
    nc := ArrSize(constants);
    cond_val := NIL;
    FOR ci := 0 TO nc - 1 DO
    BEGIN
      c := ArrItem(constants, ci);
      IF NodeType(c) = 'RangeExpr' THEN
      BEGIN
        { The Python reference's codegen_case_stmt does not support a
          RangeExpr CASE constant either (it raises "Expression type
          RangeExpr not yet supported"), so rejecting it here too is
          matching that limitation, not falling short of it -- confirmed by
          running the same input through both pipelines. }
        AbortWith('codegen: a CASE label range (lo..hi) is not yet supported');
        one_cond := NIL;
      END
      ELSE
      BEGIN
        cval := CodegenExpr(c);
        IF last_val_tk <> TK_INTEGER THEN
          AbortWith('codegen: a CASE constant must be INTEGER');
        one_cond := LLVMBuildICmp(builder, LLVMIntEQ, case_val, cval, MakeCStr(''));
      END;
      IF cond_val = NIL THEN cond_val := one_cond
      ELSE cond_val := LLVMBuildOr(builder, cond_val, one_cond, MakeCStr(''));
    END;

    body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_body'));
    IF i = n - 1 THEN
    BEGIN
      IF otherwise_stmt <> NIL THEN
        next_test_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_otherwise'))
      ELSE
        next_test_bb := end_bb;
    END
    ELSE
      next_test_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('case_test'));

    LLVMBuildCondBr(builder, cond_val, body_bb, next_test_bb);

    LLVMPositionBuilderAtEnd(builder, body_bb);
    CodegenStmt(GetObj(el, 'stmt'));
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
      LLVMBuildBr(builder, end_bb);

    cur_test_bb := next_test_bb;
  END;

  IF (n = 0) OR (otherwise_stmt <> NIL) THEN
  BEGIN
    { n = 0: cur_test_bb is still the never-entered initial block (an empty
      CASE with only OTHERWISE, or entirely empty). n > 0: cur_test_bb is
      the dedicated case_otherwise block the last iteration created above,
      still needing its body emitted. Either way it must end in a branch to
      end_bb, or it is left as an unterminated block. }
    LLVMPositionBuilderAtEnd(builder, cur_test_bb);
    IF otherwise_stmt <> NIL THEN CodegenStmt(otherwise_stmt);
    IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
      LLVMBuildBr(builder, end_bb);
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE AttachUnrollHint(branch_inst: ADRMEM; count: INTEGER);
{ LLVM loop metadata is a self-referential node. Construct with a null first
  operand, then replace it with the node value itself, as required by LLVM's
  loop pass manager. }
VAR
  option_mds, loop_mds, option_md, loop_md, loop_val: ADRMEM;
  kind: CINT;
BEGIN
  option_mds := AllocPtrArray(2);
  SetPtrArrayElem(option_mds, 0, LLVMMDStringInContext2(ctx, MakeCStr('llvm.loop.unroll.count'), 22));
  SetPtrArrayElem(option_mds, 1, LLVMValueAsMetadata(LLVMConstInt(i32ty, count, 0)));
  option_md := LLVMMDNodeInContext2(ctx, option_mds, 2);
  loop_mds := AllocPtrArray(2);
  SetPtrArrayElem(loop_mds, 0, NIL);
  SetPtrArrayElem(loop_mds, 1, option_md);
  loop_md := LLVMMDNodeInContext2(ctx, loop_mds, 2);
  loop_val := LLVMMetadataAsValue(ctx, loop_md);
  { LLVM-C 20 exposes only an immutable node constructor for this path.
    This verifier-clean form records the requested count; a later textual
    self-reference pass can make it actionable to LLVM's unroller. }
  kind := LLVMGetMDKindIDInContext(ctx, MakeCStr('llvm.loop'), 9);
  LLVMSetMetadata(branch_inst, kind, loop_val);
END;

PROCEDURE CodegenWhileStmt(stmt: ADRMEM);
VAR
  loop_bb, body_bb, end_bb, cond_val: ADRMEM;
BEGIN
  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('while_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('while_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('while_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cond_val := CodegenExpr(GetObj(stmt, 'cond'));
  IF last_val_tk <> TK_BOOLEAN THEN
    AbortWith('codegen: WHILE condition must be BOOLEAN');
  LLVMBuildCondBr(builder, cond_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  loop_depth := loop_depth + 1;
  loop_break_blocks[loop_depth] := end_bb;
  loop_cycle_blocks[loop_depth] := loop_bb;
  loop_labels[loop_depth] := pending_loop_label;
  pending_loop_label := '';
  CodegenStmt(GetObj(stmt, 'body'));
  loop_depth := loop_depth - 1;
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
  BEGIN
    LLVMBuildBr(builder, loop_bb);
    IF GetObjOrNil(stmt, 'unroll') <> NIL THEN
      AttachUnrollHint(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)), GetInt(stmt, 'unroll'));
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenRepeatStmt(stmt: ADRMEM);
VAR
  loop_bb, end_bb, cond_val: ADRMEM;
BEGIN
  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('repeat_loop'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('repeat_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  loop_depth := loop_depth + 1;
  loop_break_blocks[loop_depth] := end_bb;
  loop_cycle_blocks[loop_depth] := loop_bb;
  loop_labels[loop_depth] := pending_loop_label;
  pending_loop_label := '';
  CodegenStmtArray(GetObj(stmt, 'body'));
  loop_depth := loop_depth - 1;
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
  BEGIN
    cond_val := CodegenExpr(GetObj(stmt, 'cond'));
    IF last_val_tk <> TK_BOOLEAN THEN
      AbortWith('codegen: REPEAT..UNTIL condition must be BOOLEAN');
    LLVMBuildCondBr(builder, cond_val, end_bb, loop_bb);
    IF GetObjOrNil(stmt, 'unroll') <> NIL THEN
      AttachUnrollHint(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)), GetInt(stmt, 'unroll'));
  END;

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenForStmt(stmt: ADRMEM);
VAR
  var_name: Str255;
  symi: INTEGER32;
  var_tk: INTEGER;
  var_llty: ADRMEM;
  start_node, end_node: ADRMEM;
  start_val, end_val, cur_val, cmp_val, next_val: ADRMEM;
  loop_bb, body_bb, step_bb, end_bb: ADRMEM;
  down: BOOLEAN;
BEGIN
  var_name := GetStr(stmt, 'var');
  symi := LookupSym(var_name);
  IF symi = 0 THEN
    AbortWith2('codegen: undefined FOR loop variable: ', var_name);
  var_tk := symbols[symi].tk;
  IF NOT IsIntegerFamilyTk(var_tk) AND (TypeKind(var_tk) <> TK_ENUM) THEN
    AbortWith('codegen: FOR loop variable must be an integer-family or enumerated type');
  var_llty := LLVMTypeForTk(var_tk);

  start_node := GetObj(stmt, 'start');
  start_val := CodegenExpr(start_node);
  start_val := CoerceForAssign(start_val, last_val_tk, var_tk, start_node, var_name);
  LLVMBuildStore(builder, start_val, symbols[symi].llvm_val);

  end_node := GetObj(stmt, 'end');
  end_val := CodegenExpr(end_node);
  end_val := CoerceForAssign(end_val, last_val_tk, var_tk, end_node, var_name);

  down := GetStr(stmt, 'direction') = 'DOWNTO';

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_body'));
  step_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_step'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('for_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_val := LLVMBuildLoad2(builder, var_llty, symbols[symi].llvm_val, MakeCStr(''));
  IF down THEN
    cmp_val := LLVMBuildICmp(builder, LLVMIntSGE, cur_val, end_val, MakeCStr(''))
  ELSE
    cmp_val := LLVMBuildICmp(builder, LLVMIntSLE, cur_val, end_val, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  loop_depth := loop_depth + 1;
  loop_break_blocks[loop_depth] := end_bb;
  loop_cycle_blocks[loop_depth] := step_bb;
  loop_labels[loop_depth] := pending_loop_label;
  pending_loop_label := '';
  CodegenStmt(GetObj(stmt, 'body'));
  loop_depth := loop_depth - 1;
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
    LLVMBuildBr(builder, step_bb);

  LLVMPositionBuilderAtEnd(builder, step_bb);
  cur_val := LLVMBuildLoad2(builder, var_llty, symbols[symi].llvm_val, MakeCStr(''));
  IF down THEN
    next_val := LLVMBuildSub(builder, cur_val, LLVMConstInt(var_llty, 1, 0), MakeCStr(''))
  ELSE
    next_val := LLVMBuildAdd(builder, cur_val, LLVMConstInt(var_llty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_val, symbols[symi].llvm_val);
  LLVMBuildBr(builder, loop_bb);
  IF GetObjOrNil(stmt, 'unroll') <> NIL THEN
    AttachUnrollHint(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)), GetInt(stmt, 'unroll'));

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE ResolveStringExprCharsLen(expr: ADRMEM; VAR chars_ptr: ADRMEM; VAR len_val: ADRMEM);
{ The counterpart of the Python reference's get_string_chars_and_len: given
  a CONST STRING-typed actual argument (a string literal, or an Identifier
  naming an LSTRING/STRING variable), returns a pointer to its first
  character plus its length as an i32 -- LSTRING's is the dynamic runtime
  length byte, STRING's is its fixed declared capacity. Scoped to what
  CONCAT/COPYLST/COPYSTR need; a designator (indexed/field string
  sub-expression) is not yet supported here. }
VAR
  strval: Str255;
  symi: INTEGER32;
  tid: INTEGER;
  addr, gep_idx, len_ptr: ADRMEM;
BEGIN
  IF NodeType(expr) = 'StringLiteral' THEN
  BEGIN
    strval := DecodeStringLiteral(GetStr(expr, 'value'));
    chars_ptr := LLVMBuildGlobalStringPtr(builder, MakeCStr(strval), MakeCStr('str'));
    len_val := LLVMConstInt(i32ty, ORD(strval[0]), 0);
  END
  ELSE IF NodeType(expr) = 'Identifier' THEN
  BEGIN
    symi := LookupSym(GetStr(expr, 'name'));
    IF (symi = 0) AND RoutineIsFunc(LookupRoutine(GetStr(expr, 'name'))) THEN
    BEGIN
      { A bare niladic-call Identifier (e.g. `CurKind = 'LBRACKET'`, an
        aggregate Str255-returning FUNCTION called without parens) has no
        symbol-table entry of its own -- materialize the call's result
        into a fresh temporary, same as ComputeDesignatorAddress and
        CodegenCallCommon's VAR-argument marshaling do for the same shape. }
      tid := routines[LookupRoutine(GetStr(expr, 'name'))].ret_tk;
      addr := EntryAlloca(LLVMTypeForTk(tid), '');
      LLVMBuildStore(builder, CodegenCallCommon(GetStr(expr, 'name'), NIL), addr);
    END
    ELSE
    BEGIN
      IF symi = 0 THEN
        AbortWith2('codegen: undefined variable: ', GetStr(expr, 'name'));
      tid := symbols[symi].tk;
      addr := symbols[symi].llvm_val;
    END;
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
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith2('codegen: not a string-typed variable: ', GetStr(expr, 'name'));
      chars_ptr := NIL;
      len_val := NIL;
    END;
  END
  ELSE IF NodeType(expr) = 'FuncCall' THEN
  BEGIN
    { An aggregate Str255-returning FUNCTION called with explicit args (e.g.
      `NodeType(expr) = 'Identifier'`, pervasive throughout this file and
      typechecker.pas) -- materialize the call's result into a fresh
      temporary, same idiom as the bare-niladic-Identifier branch above. }
    tid := routines[LookupRoutine(GetStr(expr, 'name'))].ret_tk;
    addr := EntryAlloca(LLVMTypeForTk(tid), '');
    LLVMBuildStore(builder, CodegenCallCommon(GetStr(expr, 'name'), GetObj(expr, 'args')), addr);
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
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith2('codegen: not a string-returning function call: ', GetStr(expr, 'name'));
      chars_ptr := NIL;
      len_val := NIL;
    END;
  END
  ELSE IF NodeType(expr) = 'Designator' THEN
  BEGIN
    addr := ComputeDesignatorAddress(expr);
    tid := last_val_tk;
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
    ELSE IF TypeKind(tid) = TK_STRING THEN
    BEGIN
      len_val := LLVMConstInt(i32ty, types[tid].hi, 0);
      gep_idx := AllocPtrArray(2);
      SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
      SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
      chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(tid), addr, gep_idx, 2, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith('codegen: not a string-typed designator expression');
      chars_ptr := NIL;
      len_val := NIL;
    END;
  END
  ELSE
  BEGIN
    AbortWith('codegen: unsupported string expression (only literals and bare variables are supported)');
    chars_ptr := NIL;
    len_val := NIL;
  END;
END;

PROCEDURE ResolveStringDestVar(expr: ADRMEM; VAR d_symi: INTEGER32; VAR d_tid: INTEGER;
  VAR d_addr, chars_ptr, len_val: ADRMEM);
{ The mutable-destination counterpart of ResolveStringExprCharsLen, for
  INSERT/DELETE, which need the destination's own symbol/address (to write
  a new length byte back afterward) as well as its current chars/length.
  Scoped to a bare Identifier naming an LSTRING or STRING variable, same as
  every other string-builtin destination in this file. }
VAR
  gep_idx, len_ptr: ADRMEM;
BEGIN
  IF NodeType(expr) <> 'Identifier' THEN
    AbortWith('codegen: a string builtin''s destination must be a bare LSTRING/STRING variable');
  d_symi := LookupSym(GetStr(expr, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(expr, 'name'));
  d_tid := symbols[d_symi].tk;
  d_addr := symbols[d_symi].llvm_val;
  IF TypeKind(d_tid) = TK_LSTRING THEN
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
    len_val := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
    len_val := LLVMBuildZExt(builder, len_val, i32ty, MakeCStr(''));
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
    chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  END
  ELSE IF TypeKind(d_tid) = TK_STRING THEN
  BEGIN
    len_val := LLVMConstInt(i32ty, types[d_tid].hi, 0);
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    chars_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  END
  ELSE
  BEGIN
    AbortWith2('codegen: not an LSTRING/STRING variable: ', GetStr(expr, 'name'));
    chars_ptr := NIL;
    len_val := NIL;
  END;
END;

PROCEDURE EmitByteCopyLoop(dest_ptr, src_ptr: ADRMEM; count: ADRMEM);
{ Copies `count` (an i32 LLVMValueRef) bytes one at a time from src_ptr to
  dest_ptr, via an alloca'd i32 loop counter -- the same alloca-based
  loop-variable idiom CodegenForStmt already uses, rather than building
  phi nodes by hand. Used by CONCAT/COPYLST/COPYSTR, whose source length is
  only known at runtime (an LSTRING's dynamic length byte), so the
  compile-time-known-literal shortcut CodegenLStringLiteralAssign/
  CodegenStringLiteralAssign use does not apply. }
VAR
  i_slot: ADRMEM;
  loop_bb, body_bb, end_bb: ADRMEM;
  cur_i, cmp_val, next_i: ADRMEM;
  s_ptr, d_ptr, byte_val: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  i_slot := EntryAlloca(i32ty, '');
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), i_slot);

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strcpy_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strcpy_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strcpy_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  cmp_val := LLVMBuildICmp(builder, LLVMIntSLT, cur_i, count, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, cur_i);
  s_ptr := LLVMBuildGEP2(builder, i8ty, src_ptr, gep_idx, 1, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, cur_i);
  d_ptr := LLVMBuildGEP2(builder, i8ty, dest_ptr, gep_idx, 1, MakeCStr(''));
  byte_val := LLVMBuildLoad2(builder, i8ty, s_ptr, MakeCStr(''));
  LLVMBuildStore(builder, byte_val, d_ptr);
  next_i := LLVMBuildAdd(builder, cur_i, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_i, i_slot);
  LLVMBuildBr(builder, loop_bb);

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE EmitByteFillLoop(dest_ptr: ADRMEM; count: ADRMEM; fill_byte: INTEGER);
{ Fills `count` (an i32 LLVMValueRef) bytes at dest_ptr with the constant
  byte fill_byte, via the same alloca-counter loop idiom as
  EmitByteCopyLoop. Used by COPYSTR's blank-padding (manual 11-20: bytes
  beyond the copied source, up to STRING's fixed capacity, get 0x20). }
VAR
  i_slot: ADRMEM;
  loop_bb, body_bb, end_bb: ADRMEM;
  cur_i, cmp_val, next_i: ADRMEM;
  d_ptr: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  i_slot := EntryAlloca(i32ty, '');
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), i_slot);

  loop_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strfill_loop'));
  body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strfill_body'));
  end_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('strfill_end'));

  LLVMBuildBr(builder, loop_bb);
  LLVMPositionBuilderAtEnd(builder, loop_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  cmp_val := LLVMBuildICmp(builder, LLVMIntSLT, cur_i, count, MakeCStr(''));
  LLVMBuildCondBr(builder, cmp_val, body_bb, end_bb);

  LLVMPositionBuilderAtEnd(builder, body_bb);
  cur_i := LLVMBuildLoad2(builder, i32ty, i_slot, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, cur_i);
  d_ptr := LLVMBuildGEP2(builder, i8ty, dest_ptr, gep_idx, 1, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i8ty, fill_byte, 0), d_ptr);
  next_i := LLVMBuildAdd(builder, cur_i, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));
  LLVMBuildStore(builder, next_i, i_slot);
  LLVMBuildBr(builder, loop_bb);

  LLVMPositionBuilderAtEnd(builder, end_bb);
END;

PROCEDURE CodegenCopylst(args: ADRMEM);
{ COPYLST(CONST S: STRING-or-LSTRING-or-literal; VAR D: LSTRING): copies S's
  characters into D from scratch (unlike CONCAT, which appends) and sets D's
  length byte to length(S). No RANGECK-style capacity guard, same documented
  simplification as CONCAT. }
VAR
  d_arg: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, len_ptr, src_len_byte: ADRMEM;
  dest_chars: ADRMEM;
  src_chars, src_len: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: COPYLST expects exactly 2 arguments');
  d_arg := ArrItem(args, 1);
  IF NodeType(d_arg) <> 'Identifier' THEN
    AbortWith('codegen: COPYLST''s destination must be a bare LSTRING variable');
  d_symi := LookupSym(GetStr(d_arg, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(d_arg, 'name'));
  d_tid := symbols[d_symi].tk;
  IF TypeKind(d_tid) <> TK_LSTRING THEN
    AbortWith('codegen: COPYLST''s destination must be an LSTRING variable');
  d_addr := symbols[d_symi].llvm_val;

  ResolveStringExprCharsLen(ArrItem(args, 0), src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  dest_chars := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  EmitByteCopyLoop(dest_chars, src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  src_len_byte := LLVMBuildTrunc(builder, src_len, i8ty, MakeCStr(''));
  LLVMBuildStore(builder, src_len_byte, len_ptr);
END;

PROCEDURE CodegenCopystr(args: ADRMEM);
{ COPYSTR(CONST S: STRING-or-LSTRING-or-literal; VAR D: STRING): copies S's
  characters into D from byte[0], then blank-pads the remaining bytes (from
  length(S) up to D's fixed capacity) with 0x20 -- STRING has no length
  byte, so every declared byte always holds a real character. }
VAR
  d_arg: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr: ADRMEM;
  dest_chars, pad_ptr, pad_len: ADRMEM;
  src_chars, src_len: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: COPYSTR expects exactly 2 arguments');
  d_arg := ArrItem(args, 1);
  IF NodeType(d_arg) <> 'Identifier' THEN
    AbortWith('codegen: COPYSTR''s destination must be a bare STRING variable');
  d_symi := LookupSym(GetStr(d_arg, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(d_arg, 'name'));
  d_tid := symbols[d_symi].tk;
  IF TypeKind(d_tid) <> TK_STRING THEN
    AbortWith('codegen: COPYSTR''s destination must be a STRING variable');
  d_addr := symbols[d_symi].llvm_val;

  ResolveStringExprCharsLen(ArrItem(args, 0), src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  dest_chars := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  EmitByteCopyLoop(dest_chars, src_chars, src_len);

  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, src_len);
  pad_ptr := LLVMBuildGEP2(builder, i8ty, dest_chars, gep_idx, 1, MakeCStr(''));
  pad_len := LLVMBuildSub(builder, LLVMConstInt(i32ty, types[d_tid].hi, 0), src_len, MakeCStr(''));
  EmitByteFillLoop(pad_ptr, pad_len, 32);
END;

PROCEDURE CodegenInsert(args: ADRMEM);
{ INSERT(CONST S: STRING-or-LSTRING-or-literal; VAR D: LSTRING-or-STRING;
  pos: INTEGER): shifts D's existing characters from `pos` onward right by
  length(S) (via memmove, since the shifted range overlaps itself -- a
  plain byte-by-byte forward copy like EmitByteCopyLoop would corrupt
  overlapping data here), then writes S into the gap. Only updates the
  length-prefix byte when D is an LSTRING; a STRING destination has no
  length byte to update. No RANGECK-style capacity guard, same documented
  simplification as CONCAT/COPYLST/COPYSTR. }
VAR
  src_chars, src_len: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, dst_chars, dst_len: ADRMEM;
  pos_val, pos0, new_len, tail_len, shift_offset: ADRMEM;
  dst_start, shift_dest, len_ptr, new_len_byte: ADRMEM;
  gep_idx: ADRMEM;
  call_args: ADRMEM;
  discard: ADRMEM;
BEGIN
  IF ArrSize(args) <> 3 THEN
    AbortWith('codegen: INSERT expects exactly 3 arguments');
  ResolveStringExprCharsLen(ArrItem(args, 0), src_chars, src_len);
  ResolveStringDestVar(ArrItem(args, 1), d_symi, d_tid, d_addr, dst_chars, dst_len);

  pos_val := CodegenExpr(ArrItem(args, 2));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: INSERT''s position argument must be INTEGER');
  pos0 := LLVMBuildSExt(builder, pos_val, i32ty, MakeCStr(''));
  pos0 := LLVMBuildSub(builder, pos0, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));

  new_len := LLVMBuildAdd(builder, dst_len, src_len, MakeCStr(''));
  tail_len := LLVMBuildSub(builder, dst_len, pos0, MakeCStr(''));

  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, pos0);
  dst_start := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));

  shift_offset := LLVMBuildAdd(builder, pos0, src_len, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, shift_offset);
  shift_dest := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));

  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, shift_dest);
  SetPtrArrayElem(call_args, 1, dst_start);
  SetPtrArrayElem(call_args, 2, LLVMBuildZExt(builder, tail_len, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, call_args, 3, MakeCStr(''));

  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, dst_start);
  SetPtrArrayElem(call_args, 1, src_chars);
  SetPtrArrayElem(call_args, 2, LLVMBuildZExt(builder, src_len, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, call_args, 3, MakeCStr(''));

  IF TypeKind(d_tid) = TK_LSTRING THEN
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
    new_len_byte := LLVMBuildTrunc(builder, new_len, i8ty, MakeCStr(''));
    LLVMBuildStore(builder, new_len_byte, len_ptr);
  END;
END;

PROCEDURE CodegenDelete(args: ADRMEM);
{ DELETE(VAR D: LSTRING-or-STRING; pos, count: INTEGER): removes `count`
  characters starting at `pos` by memmove-ing the remaining tail left, and
  (LSTRING only) shrinks the length-prefix byte by `count`. }
VAR
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, dst_chars, dst_len: ADRMEM;
  pos_val, count_val, start, count32, rem, new_len: ADRMEM;
  src_off, len_ptr, new_len_byte: ADRMEM;
  dst_at_start, src_at_off: ADRMEM;
  gep_idx, call_args: ADRMEM;
  discard: ADRMEM;
BEGIN
  IF ArrSize(args) <> 3 THEN
    AbortWith('codegen: DELETE expects exactly 3 arguments');
  ResolveStringDestVar(ArrItem(args, 0), d_symi, d_tid, d_addr, dst_chars, dst_len);

  pos_val := CodegenExpr(ArrItem(args, 1));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: DELETE''s position argument must be INTEGER');
  count_val := CodegenExpr(ArrItem(args, 2));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: DELETE''s count argument must be INTEGER');

  start := LLVMBuildSExt(builder, pos_val, i32ty, MakeCStr(''));
  start := LLVMBuildSub(builder, start, LLVMConstInt(i32ty, 1, 0), MakeCStr(''));
  count32 := LLVMBuildSExt(builder, count_val, i32ty, MakeCStr(''));

  src_off := LLVMBuildAdd(builder, start, count32, MakeCStr(''));
  rem := LLVMBuildSub(builder, dst_len, src_off, MakeCStr(''));

  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, start);
  dst_at_start := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, src_off);
  src_at_off := LLVMBuildGEP2(builder, i8ty, dst_chars, gep_idx, 1, MakeCStr(''));

  call_args := AllocPtrArray(3);
  SetPtrArrayElem(call_args, 0, dst_at_start);
  SetPtrArrayElem(call_args, 1, src_at_off);
  SetPtrArrayElem(call_args, 2, LLVMBuildZExt(builder, rem, i64ty, MakeCStr('')));
  discard := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, call_args, 3, MakeCStr(''));

  new_len := LLVMBuildSub(builder, dst_len, count32, MakeCStr(''));
  IF TypeKind(d_tid) = TK_LSTRING THEN
  BEGIN
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
    len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
    new_len_byte := LLVMBuildTrunc(builder, new_len, i8ty, MakeCStr(''));
    LLVMBuildStore(builder, new_len_byte, len_ptr);
  END;
END;

FUNCTION CodegenPositn(args: ADRMEM): ADRMEM;
{ POSITN(hay, needle): INTEGER -- 1-based index of the first occurrence of
  `needle` within `hay`, or 0 if absent; the search itself is entirely
  libpascalrt's runtime `positn` (positn.c), called exactly like printf. }
VAR
  hay_chars, hay_len, needle_chars, needle_len: ADRMEM;
  call_args, res32: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: POSITN expects exactly 2 arguments');
  ResolveStringExprCharsLen(ArrItem(args, 0), hay_chars, hay_len);
  ResolveStringExprCharsLen(ArrItem(args, 1), needle_chars, needle_len);
  call_args := AllocPtrArray(4);
  SetPtrArrayElem(call_args, 0, hay_chars);
  SetPtrArrayElem(call_args, 1, hay_len);
  SetPtrArrayElem(call_args, 2, needle_chars);
  SetPtrArrayElem(call_args, 3, needle_len);
  res32 := LLVMBuildCall2(builder, positn_fnty, positn_fn, call_args, 4, MakeCStr(''));
  CodegenPositn := LLVMBuildTrunc(builder, res32, i16ty, MakeCStr(''));
END;

FUNCTION CodegenScan(stop_on_equal: INTEGER; args: ADRMEM): ADRMEM;
{ SCANEQ(L, P, S, I) / SCANNE(L, P, S, I): INTEGER -- scans up to L
  characters of S starting at 1-based position I, stopping at the first
  character equal to (SCANEQ) or not equal to (SCANNE) P; returns the
  1-based position of the stopping character, entirely libpascalrt's
  runtime `scaneq`/`scanne` (scaneq.c). }
VAR
  l_val, p_val, s_chars, s_len, i_val: ADRMEM;
  call_args, res32: ADRMEM;
BEGIN
  IF ArrSize(args) <> 4 THEN
    AbortWith('codegen: SCANEQ/SCANNE expects exactly 4 arguments');
  l_val := CodegenExpr(ArrItem(args, 0));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: SCANEQ/SCANNE''s L argument must be INTEGER');
  l_val := LLVMBuildSExt(builder, l_val, i32ty, MakeCStr(''));
  p_val := CodegenExpr(ArrItem(args, 1));
  IF last_val_tk <> TK_CHAR THEN
    AbortWith('codegen: SCANEQ/SCANNE''s P argument must be CHAR');
  ResolveStringExprCharsLen(ArrItem(args, 2), s_chars, s_len);
  i_val := CodegenExpr(ArrItem(args, 3));
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: SCANEQ/SCANNE''s I argument must be INTEGER');
  i_val := LLVMBuildSExt(builder, i_val, i32ty, MakeCStr(''));

  call_args := AllocPtrArray(6);
  SetPtrArrayElem(call_args, 0, l_val);
  SetPtrArrayElem(call_args, 1, p_val);
  SetPtrArrayElem(call_args, 2, s_chars);
  SetPtrArrayElem(call_args, 3, s_len);
  SetPtrArrayElem(call_args, 4, i_val);
  SetPtrArrayElem(call_args, 5, LLVMConstInt(i32ty, stop_on_equal, 0));
  IF stop_on_equal <> 0 THEN
    res32 := LLVMBuildCall2(builder, scaneq_fnty, scaneq_fn, call_args, 6, MakeCStr(''))
  ELSE
    res32 := LLVMBuildCall2(builder, scanne_fnty, scanne_fn, call_args, 6, MakeCStr(''));
  CodegenScan := LLVMBuildTrunc(builder, res32, i16ty, MakeCStr(''));
END;

FUNCTION CodegenEncode(args: ADRMEM): ADRMEM;
{ ENCODE(VAR D: LSTRING; value: INTEGER): BOOLEAN -- formats `value` as
  decimal text into D via libpascalrt's runtime `encode_value`
  (encode_decode.c), which also sets D's length-prefix byte on success.
  WRITE-style `value:width` is supported (the width becomes encode_value's
  minimum field width); `:precision` is accepted syntactically but ignored,
  matching the runtime (REAL formatting is not implemented there either).
  Scoped to an LSTRING destination and an INTEGER value, matching every
  test/usage this file has verified against; the reference's own signature
  is looser (dest could in principle be any string kind) but ENCODE always
  needs to write a length-prefix byte in every real usage, so LSTRING-only
  is not a meaningful narrowing in practice. }
VAR
  dest_expr, value_expr: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, dest_chars, dest_len_unused: ADRMEM;
  val, width_val: ADRMEM;
  call_args: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: ENCODE expects exactly 2 arguments');
  dest_expr := GetObj(ArrItem(args, 0), 'expr');
  ResolveStringDestVar(dest_expr, d_symi, d_tid, d_addr, dest_chars, dest_len_unused);
  IF TypeKind(d_tid) <> TK_LSTRING THEN
    AbortWith('codegen: ENCODE''s destination must be an LSTRING variable');

  value_expr := GetObj(ArrItem(args, 1), 'expr');
  val := CodegenExpr(value_expr);
  IF last_val_tk <> TK_INTEGER THEN
    AbortWith('codegen: ENCODE''s value argument must be INTEGER');
  val := LLVMBuildSExt(builder, val, i32ty, MakeCStr(''));

  IF GetObjOrNil(ArrItem(args, 1), 'width') <> NIL THEN
  BEGIN
    width_val := CodegenExpr(GetObj(ArrItem(args, 1), 'width'));
    IF last_val_tk <> TK_INTEGER THEN
      AbortWith('codegen: ENCODE''s width argument must be INTEGER');
    width_val := LLVMBuildSExt(builder, width_val, i32ty, MakeCStr(''));
  END
  ELSE
    width_val := LLVMConstInt(i32ty, 0, 0);

  call_args := AllocPtrArray(7);
  SetPtrArrayElem(call_args, 0, dest_chars);
  SetPtrArrayElem(call_args, 1, LLVMConstInt(i32ty, types[d_tid].hi, 0));
  SetPtrArrayElem(call_args, 2, LLVMBuildBitCast(builder, d_addr, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(call_args, 3, val);
  SetPtrArrayElem(call_args, 4, width_val);
  SetPtrArrayElem(call_args, 5, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(call_args, 6, LLVMConstInt(i32ty, 0, 0));
  CodegenEncode := LLVMBuildICmp(builder, LLVMIntNE,
    LLVMBuildCall2(builder, encode_fnty, encode_fn, call_args, 7, MakeCStr('')),
    LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
END;

FUNCTION CodegenDecode(args: ADRMEM): ADRMEM;
{ DECODE(src: STRING-or-LSTRING-or-literal; VAR dest: INTEGER-or-CHAR):
  BOOLEAN -- parses a decimal integer out of `src` and stores it into
  `dest`, via libpascalrt's runtime `decode_value`. dest_size (the write's
  byte width) is derived from dest's own declared scalar type -- scoped to
  INTEGER (2 bytes) and CHAR (1 byte), the two dest_size cases
  decode_value's own manual documents by name; anything else is rejected
  rather than guessing a width. }
VAR
  src_expr, dest_expr: ADRMEM;
  src_chars, src_len: ADRMEM;
  d_symi: INTEGER32;
  d_addr: ADRMEM;
  dest_size: INTEGER;
  call_args: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: DECODE expects exactly 2 arguments');
  src_expr := GetObj(ArrItem(args, 0), 'expr');
  ResolveStringExprCharsLen(src_expr, src_chars, src_len);

  dest_expr := GetObj(ArrItem(args, 1), 'expr');
  IF NodeType(dest_expr) <> 'Identifier' THEN
    AbortWith('codegen: DECODE''s destination must be a bare INTEGER/CHAR variable');
  d_symi := LookupSym(GetStr(dest_expr, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(dest_expr, 'name'));
  d_addr := symbols[d_symi].llvm_val;
  IF symbols[d_symi].tk = TK_INTEGER THEN dest_size := 2
  ELSE IF symbols[d_symi].tk = TK_CHAR THEN dest_size := 1
  ELSE
  BEGIN
    AbortWith('codegen: DECODE''s destination must be INTEGER or CHAR');
    dest_size := 0;
  END;

  call_args := AllocPtrArray(7);
  SetPtrArrayElem(call_args, 0, src_chars);
  SetPtrArrayElem(call_args, 1, src_len);
  SetPtrArrayElem(call_args, 2, LLVMBuildBitCast(builder, d_addr, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(call_args, 3, LLVMConstInt(i32ty, dest_size, 0));
  SetPtrArrayElem(call_args, 4, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(call_args, 5, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(call_args, 6, LLVMConstInt(i32ty, 0, 0));
  CodegenDecode := LLVMBuildICmp(builder, LLVMIntNE,
    LLVMBuildCall2(builder, decode_fnty, decode_fn, call_args, 7, MakeCStr('')),
    LLVMConstInt(i32ty, 0, 0), MakeCStr(''));
END;

PROCEDURE CodegenConcat(args: ADRMEM);
{ CONCAT(VAR D: LSTRING; CONST S: STRING): appends S's characters to D and
  grows D's length byte by length(S) -- manual 11-20. No RANGECK-style
  capacity guard yet (matches this file's documented MATHCK/RANGECK
  simplification elsewhere: a capacity overflow here just corrupts memory,
  same as an unchecked array index). }
VAR
  d_arg: ADRMEM;
  d_symi: INTEGER32;
  d_tid: INTEGER;
  d_addr, len_ptr, dest_len_byte, dest_len, new_len, new_len_byte: ADRMEM;
  dest_chars, append_ptr: ADRMEM;
  src_chars, src_len: ADRMEM;
  gep_idx: ADRMEM;
BEGIN
  IF ArrSize(args) <> 2 THEN
    AbortWith('codegen: CONCAT expects exactly 2 arguments');
  d_arg := ArrItem(args, 0);
  IF NodeType(d_arg) <> 'Identifier' THEN
    AbortWith('codegen: CONCAT''s destination must be a bare LSTRING variable');
  d_symi := LookupSym(GetStr(d_arg, 'name'));
  IF d_symi = 0 THEN
    AbortWith2('codegen: undefined variable: ', GetStr(d_arg, 'name'));
  d_tid := symbols[d_symi].tk;
  IF TypeKind(d_tid) <> TK_LSTRING THEN
    AbortWith('codegen: CONCAT''s destination must be an LSTRING variable');
  d_addr := symbols[d_symi].llvm_val;

  ResolveStringExprCharsLen(ArrItem(args, 1), src_chars, src_len);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  len_ptr := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  dest_len_byte := LLVMBuildLoad2(builder, i8ty, len_ptr, MakeCStr(''));
  dest_len := LLVMBuildZExt(builder, dest_len_byte, i32ty, MakeCStr(''));
  new_len := LLVMBuildAdd(builder, dest_len, src_len, MakeCStr(''));

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  dest_chars := LLVMBuildGEP2(builder, LLVMTypeForTk(d_tid), d_addr, gep_idx, 2, MakeCStr(''));
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, dest_len);
  append_ptr := LLVMBuildGEP2(builder, i8ty, dest_chars, gep_idx, 1, MakeCStr(''));
  EmitByteCopyLoop(append_ptr, src_chars, src_len);

  new_len_byte := LLVMBuildTrunc(builder, new_len, i8ty, MakeCStr(''));
  LLVMBuildStore(builder, new_len_byte, len_ptr);
END;

FUNCTION LaunchI64(v: ADRMEM; tk: INTEGER): ADRMEM;
BEGIN
  IF (tk = TK_INTEGER64) OR (tk = TK_WORD64) THEN LaunchI64 := v
  ELSE IF IsUnsignedWordTk(tk) THEN LaunchI64 := LLVMBuildZExt(builder, v, i64ty, MakeCStr(''))
  ELSE LaunchI64 := LLVMBuildSExt(builder, v, i64ty, MakeCStr(''));
END;

FUNCTION EmitLaunchThunk(ridx: INTEGER32): ADRMEM;
{ Emit the CPU-device entry adapter: void(i8** argv). Each argv slot points
  to a typed argument cell, exactly as pas_dev_launch expects. }
VAR
  thunk_name: Str255;
  thunk_ty, thunk, thunk_bb, saved_bb, saved_fn: ADRMEM;
  argv, slot_addr, slot, typed, val: ADRMEM;
  indices, call_args: ADRMEM;
  i: INTEGER32;
BEGIN
  thunk_name := '__pas_klaunch_';
  CONCAT(thunk_name, routines[ridx].name);
  thunk_ty := LLVMFunctionType(voidty, MakeArgs1(LLVMPointerType(i8ptrty, 0)), 1, 0);
  thunk := LLVMAddFunction(modl, MakeCStr(thunk_name), thunk_ty);
  LLVMSetLinkage(thunk, 8); { LLVMInternalLinkage -- reached only through the
                              registry, never by name from another object. }
  thunk_bb := LLVMAppendBasicBlockInContext(ctx, thunk, MakeCStr('entry'));
  saved_bb := LLVMGetInsertBlock(builder);
  saved_fn := cur_fn;
  LLVMPositionBuilderAtEnd(builder, thunk_bb);
  cur_fn := thunk;
  argv := LLVMGetParam(thunk, 0);
  call_args := AllocPtrArray(routines[ridx].nparams);
  FOR i := 0 TO routines[ridx].nparams - 1 DO
  BEGIN
    indices := AllocPtrArray(1);
    SetPtrArrayElem(indices, 0, LLVMConstInt(i32ty, i, 0));
    slot_addr := LLVMBuildGEP2(builder, i8ptrty, argv, indices, 1, MakeCStr(''));
    slot := LLVMBuildLoad2(builder, i8ptrty, slot_addr, MakeCStr(''));
    typed := LLVMBuildBitCast(builder, slot,
      LLVMPointerType(LLVMTypeForTk(routines[ridx].param_tk[i + 1]), 0), MakeCStr(''));
    val := LLVMBuildLoad2(builder, LLVMTypeForTk(routines[ridx].param_tk[i + 1]), typed, MakeCStr(''));
    SetPtrArrayElem(call_args, i, val);
  END;
  val := LLVMBuildCall2(builder, routines[ridx].fnty, routines[ridx].fn,
    call_args, routines[ridx].nparams, MakeCStr(''));
  LLVMBuildRetVoid(builder);
  cur_fn := saved_fn;
  LLVMPositionBuilderAtEnd(builder, saved_bb);
  EmitLaunchThunk := thunk;
END;

FUNCTION LaunchRegistryPtr: ADRMEM;
{ An i8* to this compiland's kernel registry global -- the CPU stand-in for a
  loaded CUDA module. The global is a shell here; EmitLaunchRegistry fills it
  once every LAUNCH has recorded its kernel. Under the CUDA backend there is
  no in-process registry (the kernel is the loaded PTX module and the shim
  ignores this argument), so a null pointer is passed rather than referencing
  a registry global nothing would define. }
VAR
  elems: ADRMEM;
BEGIN
  IF device_backend_cuda THEN
    LaunchRegistryPtr := LLVMConstPointerNull(i8ptrty)
  ELSE
  BEGIN
    IF klaunch_registry_gv = NIL THEN
    BEGIN
      elems := AllocPtrArray(3);
      SetPtrArrayElem(elems, 0, LLVMPointerType(i8ptrty, 0));
      SetPtrArrayElem(elems, 1, LLVMPointerType(i8ptrty, 0));
      SetPtrArrayElem(elems, 2, i64ty);
      klaunch_registry_ty := LLVMStructTypeInContext(ctx, elems, 3, 0);
      klaunch_registry_gv := LLVMAddGlobal(modl, klaunch_registry_ty, MakeCStr('__pas_klaunch_registry'));
      LLVMSetGlobalConstant(klaunch_registry_gv, 1);
    END;
    LaunchRegistryPtr := LLVMConstBitCast(klaunch_registry_gv, i8ptrty);
  END;
END;

FUNCTION DevicePtxPtr: ADRMEM;
{ An i8* to the device-PTX blob the loader consumes. The CPU device never
  executes it -- its "module" is the registry -- but the mechanism is always
  present so swapping in the CUDA shim is a pure runtime change. Under the
  CUDA backend the blob is an external symbol built from the device unit's
  own .ptx at link time, so the host object neither bakes the kernel text in
  nor depends on the device artifact. }
BEGIN
  IF device_ptx_gv = NIL THEN
  BEGIN
    IF device_backend_cuda THEN
    BEGIN
      device_ptx_gv := LLVMAddGlobal(modl, LLVMArrayType(i8ty, 0), MakeCStr('__pas_device_ptx'));
      LLVMSetGlobalConstant(device_ptx_gv, 1);
      device_ptx_ptr_val := LLVMConstBitCast(device_ptx_gv, i8ptrty);
    END
    ELSE
    BEGIN
      device_ptx_ptr_val := LLVMBuildGlobalStringPtr(builder, MakeCStr(''), MakeCStr('__pas_device_ptx'));
      device_ptx_gv := device_ptx_ptr_val;
    END;
  END;
  DevicePtxPtr := device_ptx_ptr_val;
END;

FUNCTION LaunchThunkFor(ridx: INTEGER32): ADRMEM;
{ The dispatch thunk for this kernel, emitted once and recorded in the
  registry. A second LAUNCH of the same kernel reuses it -- emitting it again
  would silently uniquify the symbol into a second, unregistered thunk. }
VAR
  i, found: INTEGER32;
  kname: Str255;
  thunk: ADRMEM;
BEGIN
  { The name is copied to a local before the comparison because this file's
    own string-comparison lowering (IsStringShapedExpr) recognizes only a
    bare identifier or literal as string-shaped: with a selector-bearing
    designator on *both* sides it falls through to the scalar path and
    rejects the operands outright. }
  kname := routines[ridx].name;
  found := 0;
  FOR i := 1 TO nkernels DO
    IF kernel_name_tab[i] = kname THEN found := i;
  IF found <> 0 THEN LaunchThunkFor := kernel_thunk_tab[found]
  ELSE
  BEGIN
    IF nkernels >= MAX_KERNELS THEN AbortWith('codegen: too many launched kernels');
    thunk := EmitLaunchThunk(ridx);
    nkernels := nkernels + 1;
    kernel_name_tab[nkernels] := kname;
    kernel_thunk_tab[nkernels] := thunk;
    LaunchThunkFor := thunk;
  END;
END;

PROCEDURE EmitLaunchRegistry;
{ Fill the registry global from the launched-kernel list: a names table, an
  entries (thunk) table, and the i8** names / i8** entries / i64 count
  struct the shim's by-name lookup walks. A no-op for a compiland that
  performed no launches, so launch-free output is unchanged. }
VAR
  names_vals, ent_vals, fields: ADRMEM;
  names_gv, ent_gv: ADRMEM;
  i: INTEGER32;
BEGIN
  IF (klaunch_registry_gv <> NIL) AND (nkernels > 0) THEN
  BEGIN
    names_vals := AllocPtrArray(nkernels);
    ent_vals := AllocPtrArray(nkernels);
    FOR i := 1 TO nkernels DO
    BEGIN
      SetPtrArrayElem(names_vals, i - 1,
        LLVMBuildGlobalStringPtr(builder, MakeCStr(kernel_name_tab[i]), MakeCStr('kregname')));
      SetPtrArrayElem(ent_vals, i - 1, LLVMConstBitCast(kernel_thunk_tab[i], i8ptrty));
    END;
    names_gv := LLVMAddGlobal(modl, LLVMArrayType(i8ptrty, nkernels), MakeCStr('__pas_kregnames'));
    LLVMSetGlobalConstant(names_gv, 1);
    LLVMSetInitializer(names_gv, LLVMConstArray(i8ptrty, names_vals, nkernels));
    ent_gv := LLVMAddGlobal(modl, LLVMArrayType(i8ptrty, nkernels), MakeCStr('__pas_kregentries'));
    LLVMSetGlobalConstant(ent_gv, 1);
    LLVMSetInitializer(ent_gv, LLVMConstArray(i8ptrty, ent_vals, nkernels));
    fields := AllocPtrArray(3);
    SetPtrArrayElem(fields, 0, LLVMConstBitCast(names_gv, LLVMPointerType(i8ptrty, 0)));
    SetPtrArrayElem(fields, 1, LLVMConstBitCast(ent_gv, LLVMPointerType(i8ptrty, 0)));
    SetPtrArrayElem(fields, 2, LLVMConstInt(i64ty, nkernels, 0));
    LLVMSetInitializer(klaunch_registry_gv, LLVMConstStructInContext(ctx, fields, 3, 0));
  END;
END;

PROCEDURE CodegenLaunch(args: ADRMEM);
{ Host launch ABI: LAUNCH(kernel, grid, block, actuals...) or its six-value
  geometry form. It uses the CPU shim's real void** ABI and a dispatch thunk. }
VAR
  kernel, actual: ADRMEM;
  kernel_name: Str255;
  ridx, n, expected, i: INTEGER32;
  grid, block, val, cell, argv, argv_ptr, thunk: ADRMEM;
  dev_module, entry: ADRMEM;
  geom: ARRAY[1..6] OF ADRMEM;
  actual_tk: INTEGER;
  indices, call_args: ADRMEM;
BEGIN
  n := ArrSize(args);
  IF n < 3 THEN AbortWith('codegen: LAUNCH needs kernel, grid, and block');
  kernel := ArrItem(args, 0);
  IF NodeType(kernel) <> 'Identifier' THEN
    AbortWith('codegen: LAUNCH kernel must be an identifier');
  kernel_name := GetStr(kernel, 'name');
  ridx := LookupRoutine(kernel_name);
  IF ridx = 0 THEN AbortWith2('codegen: unknown LAUNCH kernel: ', kernel_name);
  expected := routines[ridx].nparams;
  IF (n <> expected + 3) AND (n <> expected + 7) THEN
    AbortWith('codegen: LAUNCH expects 2 or 6 geometry values');
  IF n = expected + 3 THEN
  BEGIN
    grid := CodegenExpr(ArrItem(args, 1));
    grid := LaunchI64(grid, last_val_tk);
    block := CodegenExpr(ArrItem(args, 2));
    block := LaunchI64(block, last_val_tk);
    geom[1] := grid; geom[2] := LLVMConstInt(i64ty, 1, 0); geom[3] := LLVMConstInt(i64ty, 1, 0);
    geom[4] := block; geom[5] := LLVMConstInt(i64ty, 1, 0); geom[6] := LLVMConstInt(i64ty, 1, 0);
  END
  ELSE
    FOR i := 1 TO 6 DO
    BEGIN
      geom[i] := CodegenExpr(ArrItem(args, i));
      geom[i] := LaunchI64(geom[i], last_val_tk);
    END;
  argv := EntryAlloca(LLVMArrayType(i8ptrty, expected), 'launch_argv');
  FOR i := 0 TO expected - 1 DO
  BEGIN
    IF n = expected + 3 THEN actual := ArrItem(args, i + 3)
    ELSE actual := ArrItem(args, i + 7);
    val := CodegenExpr(actual);
    actual_tk := last_val_tk;
    val := CoerceForAssign(val, actual_tk, routines[ridx].param_tk[i + 1], actual, kernel_name);
    cell := EntryAlloca(LLVMTypeForTk(routines[ridx].param_tk[i + 1]), 'launch_arg');
    LLVMBuildStore(builder, val, cell);
    indices := AllocPtrArray(2);
    SetPtrArrayElem(indices, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(indices, 1, LLVMConstInt(i32ty, i, 0));
    indices := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, expected), argv, indices, 2, MakeCStr(''));
    val := LLVMBuildBitCast(builder, cell, i8ptrty, MakeCStr(''));
    LLVMBuildStore(builder, val, indices);
  END;
  indices := AllocPtrArray(2);
  SetPtrArrayElem(indices, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(indices, 1, LLVMConstInt(i32ty, 0, 0));
  argv_ptr := LLVMBuildGEP2(builder, LLVMArrayType(i8ptrty, expected), argv, indices, 2, MakeCStr(''));
  { Resolve the entry the way the CUDA driver does -- load the module, then
    look the kernel up in it by name -- so the same call site serves both
    backends. On the CPU device the module is this compiland's registry and
    the resolved entry is the dispatch thunk; under the CUDA backend the
    module is the loaded PTX and the shim dispatches by name, so no thunk or
    registry is emitted at all (the host object then has no undefined kernel
    symbol and needs no separate host-ABI device compile). }
  IF NOT device_backend_cuda THEN thunk := LaunchThunkFor(ridx);
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, LaunchRegistryPtr);
  SetPtrArrayElem(call_args, 1, DevicePtxPtr);
  dev_module := LLVMBuildCall2(builder, module_load_fnty, module_load_fn, call_args, 2, MakeCStr(''));
  call_args := AllocPtrArray(2);
  SetPtrArrayElem(call_args, 0, dev_module);
  SetPtrArrayElem(call_args, 1, LLVMBuildGlobalStringPtr(builder, MakeCStr(kernel_name), MakeCStr('kname')));
  entry := LLVMBuildCall2(builder, module_getfn_fnty, module_getfn_fn, call_args, 2, MakeCStr(''));
  call_args := AllocPtrArray(8);
  SetPtrArrayElem(call_args, 0, entry);
  SetPtrArrayElem(call_args, 1, geom[1]);
  SetPtrArrayElem(call_args, 2, geom[2]);
  SetPtrArrayElem(call_args, 3, geom[3]);
  SetPtrArrayElem(call_args, 4, geom[4]);
  SetPtrArrayElem(call_args, 5, geom[5]);
  SetPtrArrayElem(call_args, 6, geom[6]);
  SetPtrArrayElem(call_args, 7, argv_ptr);
  val := LLVMBuildCall2(builder, launch_fnty, launch_fn, call_args, 8, MakeCStr(''));
END;

PROCEDURE CodegenDeviceSync(name: Str255);
{ DEVICE synchronization. CPU-device execution is serial, so SYNCTHREADS is
  a no-op there; NVPTX lowers it to the hardware block barrier. }
VAR
  fnty, fn: ADRMEM;
  discard: ADRMEM;
BEGIN
  IF name <> 'SYNCTHREADS' THEN
    AbortWith2('codegen: unknown device synchronization builtin: ', name);
  IF is_nvptx_device THEN
  BEGIN
    fnty := LLVMFunctionType(voidty, NIL, 0, 0);
    fn := LLVMGetNamedFunction(modl, MakeCStr('llvm.nvvm.barrier0'));
    IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('llvm.nvvm.barrier0'), fnty);
    discard := LLVMBuildCall2(builder, fnty, fn, NIL, 0, MakeCStr(''));
  END;
END;

FUNCTION CoerceToI8Ptr(v: ADRMEM; tk: INTEGER): ADRMEM;
{ A device orchestration address argument may already be the opaque i8*
  representation (ADRMEM, e.g. DEVALLOC's own result) or a typed ^T POINTER
  value; either way the shim's C signature wants a flat i8*. }
BEGIN
  IF tk = TK_ADRMEM THEN CoerceToI8Ptr := v
  ELSE CoerceToI8Ptr := LLVMBuildBitCast(builder, v, i8ptrty, MakeCStr(''));
END;

PROCEDURE CodegenDeviceOrchestration(name: Str255; args: ADRMEM);
{ Lower DEVCOPYTO/DEVCOPYFROM/DEVFREE (Milestone D, host-only) to the
  orchestration shim externs. Mirrors the Python reference's
  _codegen_device_orchestration (stmts.py). DEVALLOC is the expression-form
  sibling, handled in CodegenExpr's FuncCall dispatch. }
VAR
  a0, a1, nbytes, call_args: ADRMEM;
  tk0, tk1: INTEGER;
  discard: ADRMEM;
BEGIN
  IF is_device_compiland THEN
    AbortWith2('codegen: host-only and cannot appear in DEVICE code: ', name);
  IF (name = 'DEVCOPYTO') OR (name = 'DEVCOPYFROM') THEN
  BEGIN
    IF ArrSize(args) <> 3 THEN AbortWith2('codegen: expects 3 arguments: ', name);
    a0 := CodegenExpr(ArrItem(args, 0)); tk0 := last_val_tk;
    a1 := CodegenExpr(ArrItem(args, 1)); tk1 := last_val_tk;
    nbytes := CodegenExpr(ArrItem(args, 2)); nbytes := LaunchI64(nbytes, last_val_tk);
    call_args := AllocPtrArray(3);
    SetPtrArrayElem(call_args, 0, CoerceToI8Ptr(a0, tk0));
    SetPtrArrayElem(call_args, 1, CoerceToI8Ptr(a1, tk1));
    SetPtrArrayElem(call_args, 2, nbytes);
    IF name = 'DEVCOPYTO' THEN
      discard := LLVMBuildCall2(builder, dev_copy_to_fnty, dev_copy_to_fn, call_args, 3, MakeCStr(''))
    ELSE
      discard := LLVMBuildCall2(builder, dev_copy_from_fnty, dev_copy_from_fn, call_args, 3, MakeCStr(''));
  END
  ELSE IF name = 'DEVFREE' THEN
  BEGIN
    IF ArrSize(args) <> 1 THEN AbortWith2('codegen: expects 1 argument: ', name);
    a0 := CodegenExpr(ArrItem(args, 0)); tk0 := last_val_tk;
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, CoerceToI8Ptr(a0, tk0));
    discard := LLVMBuildCall2(builder, dev_free_fnty, dev_free_fn, call_args, 1, MakeCStr(''));
  END
  ELSE
    AbortWith2('codegen: unknown device orchestration builtin: ', name);
END;

PROCEDURE CodegenProcCallStmt(stmt: ADRMEM);
VAR
  name: Str255;
  discard: ADRMEM;
  args, arg0: ADRMEM;
  symi: INTEGER32;
  ptr_tid, pointee_tid: INTEGER;
  raw, casted, call_args, bound, bytes, header: ADRMEM;
  narg: INTEGER32;
  fcb_ptr, assign_chars, assign_len: ADRMEM;
BEGIN
  name := GetStr(stmt, 'name');
  IF name = 'LAUNCH' THEN
    CodegenLaunch(GetObj(stmt, 'args'))
  ELSE IF is_device_compiland AND (name = 'SYNCTHREADS') THEN
    CodegenDeviceSync(name)
  ELSE IF (name = 'DEVCOPYTO') OR (name = 'DEVCOPYFROM') OR (name = 'DEVFREE') THEN
    CodegenDeviceOrchestration(name, GetObj(stmt, 'args'))
  ELSE IF name = 'WRITELN' THEN
    CodegenWriteArgs(GetObj(stmt, 'args'), TRUE)
  ELSE IF name = 'WRITE' THEN
    CodegenWriteArgs(GetObj(stmt, 'args'), FALSE)
  ELSE IF (name = 'READLN') THEN
    CodegenReadArgs(GetObj(stmt, 'args'), TRUE)
  ELSE IF (name = 'READ') THEN
    CodegenReadArgs(GetObj(stmt, 'args'), FALSE)
  ELSE IF (name = 'READSET') THEN
    CodegenReadSet(GetObj(stmt, 'args'))
  ELSE IF (name = 'RESET') OR (name = 'REWRITE') OR (name = 'GET') OR
          (name = 'PUT') OR (name = 'CLOSE') OR (name = 'DISCARD') THEN
  BEGIN
    args := GetObj(stmt, 'args');
    arg0 := ArrItem(args, 0);
    fcb_ptr := LoadFileFcbPtr(GetStr(arg0, 'name'));
    call_args := AllocPtrArray(1);
    SetPtrArrayElem(call_args, 0, fcb_ptr);
    IF name = 'RESET' THEN
      discard := LLVMBuildCall2(builder, file_reset_fnty, file_reset_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'REWRITE' THEN
      discard := LLVMBuildCall2(builder, file_rewrite_fnty, file_rewrite_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'GET' THEN
      discard := LLVMBuildCall2(builder, file_get_fnty, file_get_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'PUT' THEN
      discard := LLVMBuildCall2(builder, file_put_fnty, file_put_fn, call_args, 1, MakeCStr(''))
    ELSE IF name = 'CLOSE' THEN
      discard := LLVMBuildCall2(builder, file_close_fnty, file_close_fn, call_args, 1, MakeCStr(''))
    ELSE
      discard := LLVMBuildCall2(builder, file_discard_fnty, file_discard_fn, call_args, 1, MakeCStr(''));
  END
  ELSE IF name = 'ASSIGN' THEN
  BEGIN
    args := GetObj(stmt, 'args');
    arg0 := ArrItem(args, 0);
    fcb_ptr := LoadFileFcbPtr(GetStr(arg0, 'name'));
    ResolveStringExprCharsLen(ArrItem(args, 1), assign_chars, assign_len);
    call_args := AllocPtrArray(3);
    SetPtrArrayElem(call_args, 0, fcb_ptr);
    SetPtrArrayElem(call_args, 1, assign_chars);
    SetPtrArrayElem(call_args, 2, assign_len);
    discard := LLVMBuildCall2(builder, file_assign_fnty, file_assign_fn, call_args, 3, MakeCStr(''));
  END
  ELSE IF name = 'CONCAT' THEN
    CodegenConcat(GetObj(stmt, 'args'))
  ELSE IF name = 'COPYLST' THEN
    CodegenCopylst(GetObj(stmt, 'args'))
  ELSE IF name = 'COPYSTR' THEN
    CodegenCopystr(GetObj(stmt, 'args'))
  ELSE IF name = 'INSERT' THEN
    CodegenInsert(GetObj(stmt, 'args'))
  ELSE IF name = 'DELETE' THEN
    CodegenDelete(GetObj(stmt, 'args'))
  ELSE IF name = 'POSITN' THEN
    discard := CodegenPositn(GetObj(stmt, 'args'))
  ELSE IF name = 'SCANEQ' THEN
    discard := CodegenScan(1, GetObj(stmt, 'args'))
  ELSE IF name = 'SCANNE' THEN
    discard := CodegenScan(0, GetObj(stmt, 'args'))
  ELSE IF name = 'ENCODE' THEN
    discard := CodegenEncode(GetObj(stmt, 'args'))
  ELSE IF name = 'DECODE' THEN
    discard := CodegenDecode(GetObj(stmt, 'args'))
  ELSE IF (name = 'NEW') OR (name = 'DISPOSE') THEN
  BEGIN
    args := GetObj(stmt, 'args');
    narg := ArrSize(args);
    IF ((name = 'DISPOSE') AND (narg <> 1)) OR
       ((name = 'NEW') AND (narg <> 1) AND (narg <> 2)) THEN
      AbortWith2('codegen: wrong argument count for: ', name);
    arg0 := ArrItem(args, 0);
    IF NodeType(arg0) <> 'Identifier' THEN
      AbortWith2('codegen: argument must be a bare pointer variable: ', name);
    symi := LookupSym(GetStr(arg0, 'name'));
    IF symi = 0 THEN
      AbortWith2('codegen: undefined variable: ', GetStr(arg0, 'name'));
    ptr_tid := symbols[symi].tk;
    IF TypeKind(ptr_tid) <> TK_POINTER THEN
      AbortWith2('codegen: argument is not a POINTER variable: ', name);
    IF name = 'NEW' THEN
    BEGIN
      pointee_tid := types[ptr_tid].elem_tid;
      call_args := AllocPtrArray(1);
      IF types[pointee_tid].is_super THEN
      BEGIN
        IF narg <> 2 THEN AbortWith('codegen: NEW of SUPER ARRAY needs an upper bound');
        bound := CodegenExpr(ArrItem(args, 1));
        bound := LaunchI64(bound, last_val_tk);
        { malloc holds an i64 upper-bound header followed by flat elements. }
        bytes := LLVMBuildAdd(builder, bound, LLVMConstInt(i64ty, 1 - types[pointee_tid].lo, 1), MakeCStr(''));
        bytes := LLVMBuildMul(builder, bytes, LLVMConstInt(i64ty, TypeSizeBytes(types[pointee_tid].elem_tid), 0), MakeCStr(''));
        bytes := LLVMBuildAdd(builder, bytes, LLVMConstInt(i64ty, 8, 0), MakeCStr(''));
        SetPtrArrayElem(call_args, 0, bytes);
        raw := LLVMBuildCall2(builder, malloc_fnty, malloc_fn, call_args, 1, MakeCStr(''));
        LLVMBuildStore(builder, bound, raw);
        header := LLVMBuildGEP2(builder, i8ty, raw, MakeArgs1(LLVMConstInt(i64ty, 8, 0)), 1, MakeCStr(''));
        casted := LLVMBuildBitCast(builder, header, LLVMTypeForTk(ptr_tid), MakeCStr(''));
      END
      ELSE
      BEGIN
        SetPtrArrayElem(call_args, 0, LLVMConstInt(i64ty, TypeSizeBytes(pointee_tid), 0));
        raw := LLVMBuildCall2(builder, malloc_fnty, malloc_fn, call_args, 1, MakeCStr(''));
        casted := LLVMBuildBitCast(builder, raw, LLVMTypeForTk(ptr_tid), MakeCStr(''));
      END;
      LLVMBuildStore(builder, casted, symbols[symi].llvm_val);
    END
    ELSE
    BEGIN
      raw := LLVMBuildLoad2(builder, LLVMTypeForTk(ptr_tid), symbols[symi].llvm_val, MakeCStr(''));
      casted := LLVMBuildBitCast(builder, raw, i8ptrty, MakeCStr(''));
      IF types[types[ptr_tid].elem_tid].is_super THEN
        casted := LLVMBuildGEP2(builder, i8ty, casted,
          MakeArgs1(LLVMConstInt(i64ty, -8, 1)), 1, MakeCStr(''));
      call_args := AllocPtrArray(1);
      SetPtrArrayElem(call_args, 0, casted);
      discard := LLVMBuildCall2(builder, free_fnty, free_fn, call_args, 1, MakeCStr(''));
    END;
  END
  ELSE
    discard := CodegenCallCommon(name, GetObj(stmt, 'args'));
END;

PROCEDURE CodegenReturnStmt(stmt: ADRMEM);
{ RETURN exits the current routine immediately with whatever value is
  currently held in the function's return-value alloca (the same slot
  `FuncName := ...` assigns and which the implicit end-of-body return also
  loads) -- it does not reset the result to a fixed constant. }
VAR
  ret_load: ADRMEM;
  ret_class, n_pieces: INTEGER;
  piece_kind: SysVPieceArr;
  piece_bytes: SysVPieceSzArr;
  cstruct_ty, cptr: ADRMEM;
BEGIN
  IF cur_func_name = '' THEN
    LLVMBuildRetVoid(builder)
  ELSE
  BEGIN
    { Aggregate returns are classified on demand from cur_func_ret_tk, same
      idiom as FuncRetAggClass -- so this can never disagree with the
      classification CodegenRoutineDecl already applied to cur_func_ret_slot
      itself (the sret pointer for MEMORY, or the over-aligned aggregate
      alloca for COERCED). Mirrors that procedure's own epilogue exactly. }
    ret_class := 0;
    IF IsAggregateTk(cur_func_ret_tk) THEN
      ClassifyAggregate(cur_func_ret_tk, ret_class, n_pieces, piece_kind, piece_bytes);
    IF ret_class = SYSV_CLASS_MEMORY THEN
      LLVMBuildRetVoid(builder)
    ELSE IF ret_class = SYSV_CLASS_COERCED THEN
    BEGIN
      cstruct_ty := SysVCoercedRetType(n_pieces, piece_kind, piece_bytes);
      cptr := LLVMBuildBitCast(builder, cur_func_ret_slot, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
      ret_load := LLVMBuildLoad2(builder, cstruct_ty, cptr, MakeCStr(''));
      LLVMSetAlignment(ret_load, 8);
      ret_load := LLVMBuildRet(builder, ret_load);
    END
    ELSE
    BEGIN
      ret_load := LLVMBuildLoad2(builder, LLVMTypeForTk(cur_func_ret_tk), cur_func_ret_slot, MakeCStr(''));
      ret_load := LLVMBuildRet(builder, ret_load);
    END;
  END;
END;

FUNCTION FindLabeledLoopDepth(lbl: Str255): INTEGER32;
{ Searches innermost-to-outermost (loop_depth downto 1) for the enclosing
  loop a labeled BREAK/CYCLE names -- matches the manual's BREAK <label>/
  CYCLE <label> targeting a specific enclosing loop, not just the
  innermost one. Returns 0 if no enclosing loop carries that label. }
VAR
  d: INTEGER32;
BEGIN
  FindLabeledLoopDepth := 0;
  FOR d := loop_depth DOWNTO 1 DO
    IF loop_labels[d] = lbl THEN
    BEGIN
      FindLabeledLoopDepth := d;
      BREAK;
    END;
END;

PROCEDURE CodegenBreakStmt(stmt: ADRMEM);
VAR
  lbl: Str255;
  d: INTEGER32;
BEGIN
  IF loop_depth = 0 THEN
    AbortWith('codegen: BREAK outside of a loop');
  IF GetObjOrNil(stmt, 'label') = NIL THEN
    LLVMBuildBr(builder, loop_break_blocks[loop_depth])
  ELSE
  BEGIN
    lbl := LabelKey(stmt, 'label');
    d := FindLabeledLoopDepth(lbl);
    IF d = 0 THEN AbortWith2('codegen: BREAK targets a label with no enclosing loop: ', lbl);
    LLVMBuildBr(builder, loop_break_blocks[d]);
  END;
END;

PROCEDURE CodegenCycleStmt(stmt: ADRMEM);
VAR
  lbl: Str255;
  d: INTEGER32;
BEGIN
  IF loop_depth = 0 THEN
    AbortWith('codegen: CYCLE outside of a loop');
  IF GetObjOrNil(stmt, 'label') = NIL THEN
    LLVMBuildBr(builder, loop_cycle_blocks[loop_depth])
  ELSE
  BEGIN
    lbl := LabelKey(stmt, 'label');
    d := FindLabeledLoopDepth(lbl);
    IF d = 0 THEN AbortWith2('codegen: CYCLE targets a label with no enclosing loop: ', lbl);
    LLVMBuildBr(builder, loop_cycle_blocks[d]);
  END;
END;

PROCEDURE CodegenGotoStmt(stmt: ADRMEM);
VAR
  lbl: Str255;
  li: INTEGER32;
BEGIN
  lbl := LabelKey(stmt, 'label');
  li := LookupLabel(lbl);
  IF li = 0 THEN
    AbortWith2('codegen: GOTO to undefined label (routine-local only): ', lbl);
  LLVMBuildBr(builder, labels[li].block);
END;

PROCEDURE CodegenLabelStmt(stmt: ADRMEM);
{ The label's block was already allocated by SetupFunctionLabels before this
  routine's body was codegen'd (so a forward GOTO higher up could already
  reference it). Branch into it from the current position if not already
  terminated, then continue codegen'ing the inner statement there. If that
  inner statement is itself a loop, hand its label down via
  pending_loop_label so a labeled BREAK/CYCLE elsewhere can target it. }
VAR
  lbl: Str255;
  li: INTEGER32;
  inner: ADRMEM;
  inner_nt: Str255;
BEGIN
  lbl := LabelKey(stmt, 'label');
  li := LookupLabel(lbl);
  IF li = 0 THEN
    AbortWith2('codegen: internal error: label block missing: ', lbl);
  IF LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder)) = NIL THEN
    LLVMBuildBr(builder, labels[li].block);
  LLVMPositionBuilderAtEnd(builder, labels[li].block);
  inner := GetObj(stmt, 'stmt');
  inner_nt := NodeType(inner);
  IF (inner_nt = 'WhileStmt') OR (inner_nt = 'RepeatStmt') OR (inner_nt = 'ForStmt') THEN
    pending_loop_label := lbl;
  CodegenStmt(inner);
END;

PROCEDURE CodegenWithStmt(stmt: ADRMEM);
{ WITH t1, t2, ... DO body: one PushScope per target left to right, each
  target's fields registered directly as symbols whose llvm_val IS the
  field's own GEP'd storage address (not a copy) -- so reads/writes inside
  body affect the underlying record in place, matching the reference's
  "bind field name directly to GEP pointer" (codegen/stmts.py's
  codegen_with_stmt). A later target's field of the same name shadows an
  earlier one for free, since LookupSym's backward scan finds the most
  recently appended symbol first. }
VAR
  targets, target: ADRMEM;
  ntargets, ti, fi: INTEGER32;
  base_ptr, field_ptr, gep_idx: ADRMEM;
  cur_tid: INTEGER;
  pushed: INTEGER32;
BEGIN
  targets := GetObj(stmt, 'targets');
  ntargets := ArrSize(targets);
  pushed := 0;
  FOR ti := 0 TO ntargets - 1 DO
  BEGIN
    target := ArrItem(targets, ti);
    base_ptr := ComputeDesignatorAddress(target);
    cur_tid := last_val_tk;
    IF TypeKind(cur_tid) <> TK_RECORD THEN
      AbortWith('codegen: WITH target must be a record');
    PushScope;
    pushed := pushed + 1;
    FOR fi := 1 TO nfields DO
      IF fields[fi].rec_tid = cur_tid THEN
      BEGIN
        gep_idx := AllocPtrArray(1);
        SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, fields[fi].byte_offset, 0));
        field_ptr := LLVMBuildGEP2(builder, i8ty, base_ptr, gep_idx, 1, MakeCStr(''));
        field_ptr := LLVMBuildBitCast(builder, field_ptr, LLVMPointerType(LLVMTypeForTk(fields[fi].field_tid), 0), MakeCStr(''));
        IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
        nsymbols := nsymbols + 1;
        symbols[nsymbols].name := fields[fi].fname;
        symbols[nsymbols].tk := fields[fi].field_tid;
        symbols[nsymbols].llvm_val := field_ptr;
      END;
  END;
  CodegenStmt(GetObj(stmt, 'body'));
  FOR ti := 1 TO pushed DO
    PopScope;
END;

PROCEDURE CodegenStmt(stmt: ADRMEM);
VAR
  nt, msg: Str255;
BEGIN
  EnterStmtLevel;
  nt := NodeType(stmt);
  IF nt = 'AssignStmt' THEN CodegenAssignStmt(stmt)
  ELSE IF nt = 'CompoundStmt' THEN CodegenStmtArray(GetObj(stmt, 'stmts'))
  ELSE IF nt = 'IfStmt' THEN CodegenIfStmt(stmt)
  ELSE IF nt = 'WhileStmt' THEN CodegenWhileStmt(stmt)
  ELSE IF nt = 'RepeatStmt' THEN CodegenRepeatStmt(stmt)
  ELSE IF nt = 'ForStmt' THEN CodegenForStmt(stmt)
  ELSE IF nt = 'CaseStmt' THEN CodegenCaseStmt(stmt)
  ELSE IF nt = 'ProcCallStmt' THEN CodegenProcCallStmt(stmt)
  ELSE IF nt = 'ReturnStmt' THEN CodegenReturnStmt(stmt)
  ELSE IF nt = 'BreakStmt' THEN CodegenBreakStmt(stmt)
  ELSE IF nt = 'CycleStmt' THEN CodegenCycleStmt(stmt)
  ELSE IF nt = 'LabelStmt' THEN CodegenLabelStmt(stmt)
  ELSE IF nt = 'GotoStmt' THEN CodegenGotoStmt(stmt)
  ELSE IF nt = 'WithStmt' THEN CodegenWithStmt(stmt)
  ELSE IF nt = 'EmptyStmt' THEN BEGIN END
  ELSE
  BEGIN
    msg := 'codegen: unhandled statement kind: ';
    CONCAT(msg, nt);
    AbortWith(msg);
  END;
  LeaveStmtLevel;
END;

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
