{ Type-model declarations shared by codegen lowering units. }

INTERFACE;
UNIT cg_types;
USES jsonutil, cg_base, cg_util;

CONST
  SYSV_CLASS_MEMORY = 1;
  SYSV_CLASS_COERCED = 2;
  SYSV_EB_NONE = 0;
  SYSV_EB_INTEGER = 1;
  SYSV_EB_SSE = 2;
  SYSV_EB_MEMORY = 3;
  SYSV_PIECE_INTEGER = 1;
  SYSV_PIECE_FLOAT = 2;
  SYSV_PIECE_DOUBLE = 3;
  SYSV_PIECE_SSEVEC = 4;

FUNCTION LLVMTypeForTk(tk: INTEGER): ADRMEM;
FUNCTION TypeKind(tid: INTEGER): INTEGER;
FUNCTION LookupNamedType(name: Str255): INTEGER;
FUNCTION LookupField(rec_tid: INTEGER; fname: Str255): INTEGER;
FUNCTION RegisterType(tk: INTEGER; elem_tid, lo, hi: INTEGER; llvm_ty: ADRMEM): INTEGER;
FUNCTION EnsureGenericSetType: INTEGER;
FUNCTION PointerSpacesCompatible(from_tid, to_tid: INTEGER): BOOLEAN;
FUNCTION TypesCompatibleForAssign(from_tid, to_tid: INTEGER): BOOLEAN;
FUNCTION LookupConst(name: Str255): INTEGER32;
FUNCTION FoldConstInt(expr_node: ADRMEM; VAR folded: INTEGER64): BOOLEAN;
FUNCTION IsIntLiteralLike(expr_node: ADRMEM): BOOLEAN;
FUNCTION Real64ToInt64(val: REAL): INTEGER64;
FUNCTION IntLiteralValue(expr_node: ADRMEM): INTEGER64;
FUNCTION IsWideIntTk(tk: INTEGER): BOOLEAN;
FUNCTION IsIntegerFamilyTk(tk: INTEGER): BOOLEAN;
FUNCTION IsUnsignedWordTk(tk: INTEGER): BOOLEAN;
FUNCTION IntFamilyWidth(tk: INTEGER): INTEGER;
FUNCTION CoerceForAssign(v: ADRMEM; from_tid, to_tid: INTEGER; expr_node: ADRMEM; ctx_name: Str255): ADRMEM;
FUNCTION RoundUpBytes(n, a: INTEGER32): INTEGER32;
FUNCTION TypeAlignBytes(tid: INTEGER): INTEGER32;
FUNCTION TypeSizeBytes(tid: INTEGER): INTEGER32;
FUNCTION IsAggregateTk(tk: INTEGER): BOOLEAN;
FUNCTION SysVMergeClass(a: INTEGER; b: INTEGER): INTEGER;
FUNCTION IsSysVLeafTid(tid: INTEGER): BOOLEAN;
PROCEDURE WalkTypeLeaves(tid: INTEGER; base_off: INTEGER32; VAR nleaves: INTEGER32; VAR leaf_off: SysVLeafOffArr; VAR leaf_tid: SysVLeafTidArr);
PROCEDURE ClassifyAggregate(tk: INTEGER; VAR agg_class: INTEGER; VAR n_pieces: INTEGER; VAR piece_kind: SysVPieceArr; VAR piece_bytes: SysVPieceSzArr);
FUNCTION SysVAggClass(tk: INTEGER): INTEGER;
FUNCTION SysVByvalAlign(tk: INTEGER): INTEGER32;
FUNCTION SysVPieceLLVMType(kind: INTEGER; nbytes: INTEGER32): ADRMEM;
FUNCTION SysVCoercedStructType(n_pieces: INTEGER; VAR piece_kind: SysVPieceArr; VAR piece_bytes: SysVPieceSzArr): ADRMEM;
FUNCTION SysVCoercedRetType(n_pieces: INTEGER; VAR piece_kind: SysVPieceArr; VAR piece_bytes: SysVPieceSzArr): ADRMEM;
FUNCTION SysVCoercedPiecePtr(base: ADRMEM; cstruct_ty: ADRMEM; eb: INTEGER): ADRMEM;
FUNCTION ResolveIntLiteral(node: ADRMEM): INTEGER;
FUNCTION TypeNameStrToTk(nm: Str255): INTEGER;
FUNCTION ResolveTypeExpr(te: ADRMEM): INTEGER;

END;
