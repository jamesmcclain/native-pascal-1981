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

(*$INCLUDE:'codegen_decl.inc'*)

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
