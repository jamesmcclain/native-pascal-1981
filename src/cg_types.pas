{ Implementations for cg_types. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
IMPLEMENTATION OF cg_types;

{ ============================== type model =============================== }

FUNCTION LLVMTypeForTk(tk: INTEGER): ADRMEM;
BEGIN
  IF tk = TK_INTEGER THEN LLVMTypeForTk := i16ty
  ELSE IF tk = TK_REAL THEN LLVMTypeForTk := dblty
  ELSE IF tk = TK_BOOLEAN THEN LLVMTypeForTk := i1ty
  ELSE IF tk = TK_CHAR THEN LLVMTypeForTk := i8ty
  ELSE IF tk = TK_WORD THEN LLVMTypeForTk := i16ty
  ELSE IF tk = TK_INTEGER8 THEN LLVMTypeForTk := i8ty
  ELSE IF tk = TK_WORD8 THEN LLVMTypeForTk := i8ty
  ELSE IF tk = TK_INTEGER32 THEN LLVMTypeForTk := i32ty
  ELSE IF tk = TK_WORD32 THEN LLVMTypeForTk := i32ty
  ELSE IF tk = TK_INTEGER64 THEN LLVMTypeForTk := i64ty
  ELSE IF tk = TK_WORD64 THEN LLVMTypeForTk := i64ty
  ELSE IF tk = TK_REAL32 THEN LLVMTypeForTk := f32ty
  ELSE IF tk = TK_ADRMEM THEN LLVMTypeForTk := i8ptrty
  ELSE IF tk >= 14 THEN LLVMTypeForTk := types[tk].llvm_ty
  ELSE
  BEGIN
    AbortWith('codegen: LLVMTypeForTk: unknown type kind');
    LLVMTypeForTk := NIL;
  END;
END;

FUNCTION TypeKind(tid: INTEGER): INTEGER;
{ tid <= 13 IS its own kind (a bare scalar TK_* constant); tid >= 14 is an
  index into `types`, whose own .tk says ARRAY or RECORD. }
BEGIN
  IF tid <= 13 THEN TypeKind := tid
  ELSE TypeKind := types[tid].tk;
END;

FUNCTION LookupNamedType(name: Str255): INTEGER;
{ Case-insensitive, per the manual's "Lowercase and uppercase letters are
  interchangeable, except in string literals" (IBM Pascal, Aug 1981, Syntax
  and Vocabulary). Both sides are folded rather than the table being stored
  folded, so types[].name keeps the spelling the program used for
  diagnostics. }
VAR
  i, found: INTEGER;
  uname: Str255;
BEGIN
  found := 0;
  uname := UpperStr(name);
  FOR i := 14 TO ntypes DO
    IF UpperStr(types[i].name) = uname THEN found := i;
  LookupNamedType := found;
END;

FUNCTION LookupField(rec_tid: INTEGER; fname: Str255): INTEGER;
VAR
  i, found: INTEGER;
BEGIN
  found := 0;
  FOR i := 1 TO nfields DO
    IF (fields[i].rec_tid = rec_tid) AND (fields[i].fname = fname) THEN found := i;
  LookupField := found;
END;

FUNCTION RegisterType(tk, elem_tid: INTEGER; lo, hi: INTEGER32; llvm_ty: ADRMEM): INTEGER;
BEGIN
  IF ntypes >= MAX_TYPES THEN AbortWith('codegen: too many types');
  ntypes := ntypes + 1;
  types[ntypes].name := '';
  types[ntypes].tk := tk;
  types[ntypes].elem_tid := elem_tid;
  types[ntypes].lo := lo;
  types[ntypes].hi := hi;
  types[ntypes].is_super := FALSE;
  types[ntypes].ptr_space := PTR_SPACE_PLAIN;
  types[ntypes].enum_values := NIL;
  types[ntypes].llvm_ty := llvm_ty;
  RegisterType := ntypes;
END;

FUNCTION EnsureGenericSetType: INTEGER;
{ Lazily registers (once) a canonical TK_SET table entry with no declared
  base range, for set-typed values that have no single named declared type
  of their own -- a set constructor's result, or a set binop's result.
  Every SET type shares the exact same physical layout (setty), so this is
  always a safe stand-in tid; see TypesCompatibleForAssign, which is the
  part that actually allows mixing this with a specifically-named SET type. }
BEGIN
  IF generic_set_tid = 0 THEN
    generic_set_tid := RegisterType(TK_SET, TK_INTEGER, 0, 255, setty);
  EnsureGenericSetType := generic_set_tid;
END;

PROCEDURE RejectNvptxVector;
BEGIN
  IF is_nvptx_device THEN
    AbortWith('codegen: VECTOR types are not supported in DEVICE code compiled for NVPTX; NVPTX is SIMT and scalarizes vector arithmetic 1:1');
END;

FUNCTION EnsureBoolVectorType(n: INTEGER32): INTEGER;
{ The type of a lanewise VECTOR comparison result: VECTOR [n] OF BOOLEAN,
  i.e. <n x i8> with 0/1 per lane (M0's mask storage rule). Reuses an
  existing entry -- a named mask type, or one made by an earlier compare --
  and registers one only if none has that lane count yet, exactly the
  lazy-canonical-tid trick EnsureGenericSetType uses for SET binop results. }
VAR
  i: INTEGER;
  found: INTEGER;
BEGIN
  RejectNvptxVector;
  found := 0;
  FOR i := 1 TO ntypes DO
    IF (types[i].tk = TK_VECTOR) AND (types[i].elem_tid = TK_BOOLEAN)
       AND (types[i].lo = 0) AND (types[i].hi = n - 1) THEN
      found := i;
  IF found = 0 THEN
    found := RegisterType(TK_VECTOR, TK_BOOLEAN, 0, n - 1, LLVMVectorType(i8ty, n));
  EnsureBoolVectorType := found;
END;

FUNCTION PointerSpacesCompatible(from_tid, to_tid: INTEGER): BOOLEAN;
{ Assignment compatibility between two pointer types, mirroring the reference
  type system's PointerType.equivalent_to: a plain `^T` is a wildcard against
  any pointer flavor, and two ADS pointers agree only when their spaces do
  (ADS(GLOBAL) OF T and ADS(SHARED) OF T are distinct, incompatible types).
  Without this a host PROGRAM could not hand one of its own pointers to a
  kernel declared `ADS(GLOBAL) OF T` by an imported DEVICE INTERFACE, since
  the two type_exprs register separate tids. }
BEGIN
  IF (TypeKind(from_tid) <> TK_POINTER) OR (TypeKind(to_tid) <> TK_POINTER) THEN
    PointerSpacesCompatible := FALSE
  ELSE IF (types[from_tid].ptr_space = PTR_SPACE_PLAIN) OR
          (types[to_tid].ptr_space = PTR_SPACE_PLAIN) THEN
    PointerSpacesCompatible := TRUE
  ELSE
    PointerSpacesCompatible := types[from_tid].ptr_space = types[to_tid].ptr_space;
END;

FUNCTION AggStringTypesInterchangeable(a, b: INTEGER): BOOLEAN;
{ The reference type system is structural: two LSTRING(n), or two STRING(n),
  of equal capacity are assignment- and parameter-compatible regardless of
  which TYPE declaration produced their tid (so `Str255`, `ByteStr` and
  `ArgStr`, all LSTRING(255), interoperate freely). Verified against
  `python3 -m pascal1981`: cross-named LSTRING/STRING `:=` and VAR/value
  param passing are accepted, while a capacity mismatch is still rejected.
  Mirrors the TK_SET looseness in TypesCompatibleForAssign below. A
  TypeKind of TK_LSTRING/TK_STRING implies a registered tid (>= 14), so
  reading types[].hi here is safe. }
BEGIN
  AggStringTypesInterchangeable :=
    (TypeKind(a) = TypeKind(b)) AND
    ((TypeKind(a) = TK_LSTRING) OR (TypeKind(a) = TK_STRING)) AND
    (types[a].hi = types[b].hi);
END;

FUNCTION TypesCompatibleForAssign(from_tid, to_tid: INTEGER): BOOLEAN;
{ Exact tid equality is the normal rule everywhere else in this file, but
  two SET types are freely assignment-compatible with each other regardless
  of which specific TYPE declaration (or none, for a constructor/binop
  result) produced their tid, since every SET physically is the same
  [4 x i64] bitvector -- see EnsureGenericSetType. }
BEGIN
  { The vintage "INTEGER constant changes to WORD" rule (manual): the
    Python reference only allows this for a *constant* INTEGER expression
    (its _check_word_int_assign rejects a non-constant INTEGER value here
    even though can_assign alone would accept it, requiring explicit
    WRD(...) instead). This file doesn't constant-fold arbitrary
    expressions, so it simplifies by allowing INTEGER->WORD for any
    expression, not just literals -- a deliberate, documented looseness
    relative to the reference, not an oversight. }
  { ADRMEM is, in the reference type system, literally defined as
    PointerType(CHAR_TYPE) -- the same type as this file's ^CHAR -- not a
    distinct type that merely happens to share ADRMEM's i8ptrty LLVM
    representation (see LLVMTypeForTk's TK_ADRMEM case). So ADRMEM and any
    POINTER are mutually assignment-compatible here too, matching that
    reference definition rather than inventing a new looseness. }
  { Two VECTOR types are assignment-compatible when they have the same
    element kind and lane count, regardless of which TYPE declaration (or
    none -- a comparison result via EnsureBoolVectorType, a VSPLAT/VSELECT
    result) produced the tid. Same structural rule as SET just above; every
    such vector has the identical <n x T> layout. }
  TypesCompatibleForAssign := (from_tid = to_tid) OR
    ((TypeKind(from_tid) = TK_VECTOR) AND (TypeKind(to_tid) = TK_VECTOR)
       AND (types[from_tid].elem_tid = types[to_tid].elem_tid)
       AND (types[from_tid].lo = types[to_tid].lo)
       AND (types[from_tid].hi = types[to_tid].hi)) OR
    ((TypeKind(from_tid) = TK_SET) AND (TypeKind(to_tid) = TK_SET)) OR
    ((from_tid = TK_INTEGER) AND (to_tid = TK_WORD)) OR
    ((from_tid = TK_ADRMEM) AND (TypeKind(to_tid) = TK_POINTER)) OR
    ((TypeKind(from_tid) = TK_POINTER) AND (to_tid = TK_ADRMEM)) OR
    AggStringTypesInterchangeable(from_tid, to_tid) OR
    PointerSpacesCompatible(from_tid, to_tid);
END;

FUNCTION LookupConst(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
  found: INTEGER32;
BEGIN
  found := 0;
  FOR i := 1 TO nconsts DO
    IF const_tbl[i].name = name THEN found := i;
  LookupConst := found;
END;

FUNCTION Real64ToInt64(val: REAL): INTEGER64;
{ Truncation toward zero, done in the runtime rather than with TRUNC.

  TRUNC cannot do this job. It lowers to a float-to-int conversion at this
  dialect's INTEGER width, which is 16 bits, so TRUNC(40000.0) is -25536 and
  TRUNC(100000.0) is not even a wrapped value -- an out-of-range float-to-int
  conversion is poison in LLVM, so the result is arbitrary.

  That is not a footnote. This function is how an integer literal's value is
  read out of the AST, so every literal above 32767 was destroyed here, inside
  the compiler, and the dialect was blamed for it. The previous version split
  the value into a base-1e9 high/low pair to keep each TRUNC in range, on the
  belief that TRUNC was a 32-bit conversion. It is 16-bit, so the low half
  still had to survive a TRUNC of a value up to 1e9, and did not. }
BEGIN
  Real64ToInt64 := RETYPE(INTEGER64, pas_double_to_int64(val));
END;

FUNCTION FoldConstInt(expr_node: ADRMEM; VAR folded: INTEGER64): BOOLEAN;
{ Fold the integer-only constant-expression subset used by the reference
  typechecker's _fold_const_int: literals, unary +/-, arithmetic, earlier
  integer CONSTs, and ORD/SUCC/PRED.  This is deliberately not CodegenExpr:
  callers need the untruncated value before rebuilding it at a wider target
  type for the vintage INTEGER-constant adaptation rule. }
VAR
  nt, op, nm, ch: Str255;
  left, right, q, r: INTEGER64;
  ci: INTEGER32;
  args: ADRMEM;
BEGIN
  nt := NodeType(expr_node);
  FoldConstInt := FALSE;
  IF nt = 'IntLiteral' THEN
  BEGIN
    folded := Real64ToInt64(GetReal(expr_node, 'value'));
    FoldConstInt := TRUE;
  END
  ELSE IF nt = 'CharLiteral' THEN
  BEGIN
    { A character folds to its ordinal, which is what every constant context
      that can accept one actually wants: an array bound, a set range, or an
      ORD(...) around it. The CHAR-ness is carried separately in
      const_tbl[].is_char and recovered when the value is materialized. }
    ch := GetStr(expr_node, 'value');
    folded := ORD(ch[1]);
    FoldConstInt := TRUE;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    op := GetStr(expr_node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS')) AND FoldConstInt(GetObj(expr_node, 'operand'), folded) THEN
    BEGIN
      IF op = 'MINUS' THEN folded := 0 - folded;
      FoldConstInt := TRUE;
    END;
  END
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    op := GetStr(expr_node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') OR (op = 'DIV') OR (op = 'MOD')) AND
       FoldConstInt(GetObj(expr_node, 'left'), left) AND
       FoldConstInt(GetObj(expr_node, 'right'), right) THEN
    BEGIN
      IF op = 'PLUS' THEN folded := left + right
      ELSE IF op = 'MINUS' THEN folded := left - right
      ELSE IF op = 'MUL' THEN folded := left * right
      ELSE IF right <> 0 THEN
      BEGIN
        { Match Python's // and % rather than the host's truncating DIV/MOD. }
        q := left DIV right;
        r := left MOD right;
        IF (r <> 0) AND (((left < 0) AND (right > 0)) OR ((left > 0) AND (right < 0))) THEN
          q := q - 1;
        IF op = 'DIV' THEN folded := q
        ELSE folded := left - q * right;
        FoldConstInt := TRUE;
      END
      ELSE
        FoldConstInt := FALSE;
      IF (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') THEN FoldConstInt := TRUE;
    END;
  END
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    ci := LookupConst(GetStr(expr_node, 'name'));
    IF ci <> 0 THEN
      IF NOT const_tbl[ci].is_real THEN
      BEGIN
        folded := const_tbl[ci].ival;
        FoldConstInt := TRUE;
      END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    nm := UpperStr(GetStr(expr_node, 'name'));
    args := GetObj(expr_node, 'args');
    IF ((nm = 'ORD') OR (nm = 'CHR') OR (nm = 'SUCC') OR (nm = 'PRED')) AND (ArrSize(args) = 1) AND
       FoldConstInt(ArrItem(args, 0), folded) THEN
    BEGIN
      IF nm = 'SUCC' THEN folded := folded + 1
      ELSE IF nm = 'PRED' THEN folded := folded - 1;
      FoldConstInt := TRUE;
    END;
  END;
END;

FUNCTION IsIntLiteralLike(expr_node: ADRMEM): BOOLEAN;
{ True when FoldConstInt can produce a compile-time INTEGER value. }
VAR
  folded: INTEGER64;
BEGIN
  IsIntLiteralLike := FoldConstInt(expr_node, folded);
END;


FUNCTION IntLiteralValue(expr_node: ADRMEM): INTEGER64;
{ The full signed value of an IsIntLiteralLike expression. }
VAR
  folded: INTEGER64;
BEGIN
  IF FoldConstInt(expr_node, folded) THEN
    IntLiteralValue := folded
  ELSE
  BEGIN
    AbortWith('codegen: IntLiteralValue: not a foldable integer constant');
    IntLiteralValue := 0;
  END;
END;

FUNCTION IsWideIntTk(tk: INTEGER): BOOLEAN;
{ Every integer-family scalar wider or differently-signed than plain
  INTEGER -- the set of target kinds a bare INTEGER literal operand may
  adapt to, in an assignment or (see CodegenBinOp) a same-op comparison/
  arithmetic expression, mirroring the reference's literal_context
  threading (typecheck/exprs.py). }
BEGIN
  IsWideIntTk := (tk = TK_WORD) OR (tk = TK_INTEGER8) OR (tk = TK_WORD8) OR
    (tk = TK_INTEGER32) OR (tk = TK_WORD32) OR (tk = TK_INTEGER64) OR (tk = TK_WORD64)
    OR (TypeKind(tk) = TK_ENUM); { an enum member constant (a bare INTEGER
    literal until this point) adapts to its enum sibling's i32 ordinal
    storage the same way it adapts to any wider integer target. }
END;

FUNCTION IsIntegerFamilyTk(tk: INTEGER): BOOLEAN;
BEGIN
  IsIntegerFamilyTk := (tk = TK_INTEGER) OR (tk = TK_WORD) OR (tk = TK_INTEGER8) OR (tk = TK_WORD8) OR
    (tk = TK_INTEGER32) OR (tk = TK_WORD32) OR (tk = TK_INTEGER64) OR (tk = TK_WORD64);
END;

FUNCTION IsUnsignedWordTk(tk: INTEGER): BOOLEAN;
BEGIN
  IsUnsignedWordTk := (tk = TK_WORD) OR (tk = TK_WORD8) OR (tk = TK_WORD32) OR (tk = TK_WORD64);
END;

FUNCTION IntFamilyWidth(tk: INTEGER): INTEGER;
BEGIN
  IF (tk = TK_INTEGER8) OR (tk = TK_WORD8) THEN IntFamilyWidth := 8
  ELSE IF (tk = TK_INTEGER) OR (tk = TK_WORD) THEN IntFamilyWidth := 16
  ELSE IF (tk = TK_INTEGER32) OR (tk = TK_WORD32) THEN IntFamilyWidth := 32
  ELSE IntFamilyWidth := 64;
END;

FUNCTION CoerceForAssign(v: ADRMEM; from_tid, to_tid: INTEGER; expr_node: ADRMEM; ctx_name: Str255): ADRMEM;
{ Resolve an assignment's RHS value against its target type, mirroring the
  Python reference's can_assign plus its _const_adapts_to_int_target
  exemption (consts.py): a compile-time INTEGER *literal* may flow into a
  WORD or INTEGER8 target even where TypesCompatibleForAssign alone would
  reject the tid mismatch (WORD is the same i16 as INTEGER, so the literal
  needs no coercion; INTEGER8 is i8, so the literal is truncated). A
  non-literal INTEGER expression assigned to WORD/INTEGER8 is rejected,
  same as the reference (use WRD(...) / an INTEGER8-typed expression
  explicitly). }
BEGIN
  IF TypesCompatibleForAssign(from_tid, to_tid) THEN
    CoerceForAssign := v
  ELSE IF (from_tid = TK_INTEGER) AND ((to_tid = TK_INTEGER8) OR (to_tid = TK_WORD8)) AND IsIntLiteralLike(expr_node) THEN
    CoerceForAssign := LLVMConstInt(i8ty, IntLiteralValue(expr_node), 1)
  ELSE IF (from_tid = TK_INTEGER) AND ((to_tid = TK_INTEGER32) OR (to_tid = TK_WORD32)) AND IsIntLiteralLike(expr_node) THEN
    CoerceForAssign := LLVMConstInt(i32ty, IntLiteralValue(expr_node), 1)
  ELSE IF (from_tid = TK_INTEGER) AND ((to_tid = TK_INTEGER64) OR (to_tid = TK_WORD64)) AND IsIntLiteralLike(expr_node) THEN
    CoerceForAssign := LLVMConstInt(i64ty, IntLiteralValue(expr_node), 1)
  ELSE IF (from_tid = TK_REAL32) AND (to_tid = TK_REAL) THEN
    { REAL32 widens implicitly into REAL, matching the reference. }
    CoerceForAssign := LLVMBuildFPExt(builder, v, dblty, MakeCStr(''))
  ELSE IF ((from_tid = TK_INTEGER) OR (from_tid = TK_WORD) OR (from_tid = TK_INTEGER8) OR (from_tid = TK_WORD8)
      OR (from_tid = TK_INTEGER32) OR (from_tid = TK_WORD32) OR (from_tid = TK_INTEGER64) OR (from_tid = TK_WORD64))
      AND ((to_tid = TK_REAL) OR (to_tid = TK_REAL32)) THEN
    { Integer-family -> floating: sitofp into the target float width,
      matching the reference's general C-ABI argument coercion (not just a
      literal exemption -- any integer-typed expression, e.g. cJSON_CreateNumber(int_var)). }
    CoerceForAssign := LLVMBuildSIToFP(builder, v, LLVMTypeForTk(to_tid), MakeCStr(''))
  ELSE IF TypeKind(to_tid) = TK_ENUM THEN
  BEGIN
    { An enum target stores a 0-based ordinal in i32. Enum member
      constants arrive here as TK_INTEGER i16 literals, SUCC/PRED results
      and other enum variables as enum-typed i32 values, and plain
      integer-family expressions (the manual's ordinal arithmetic) as
      their own widths -- coerce each into the i32 storage. }
    IF IsIntLiteralLike(expr_node) THEN
      CoerceForAssign := LLVMConstInt(i32ty, IntLiteralValue(expr_node), 1)
    ELSE IF TypeKind(from_tid) = TK_ENUM THEN
      CoerceForAssign := v
    ELSE IF IsIntegerFamilyTk(from_tid) THEN
    BEGIN
      IF IntFamilyWidth(from_tid) > 32 THEN
        CoerceForAssign := LLVMBuildTrunc(builder, v, i32ty, MakeCStr(''))
      ELSE IF IsUnsignedWordTk(from_tid) THEN
        CoerceForAssign := LLVMBuildZExt(builder, v, i32ty, MakeCStr(''))
      ELSE
        CoerceForAssign := LLVMBuildSExt(builder, v, i32ty, MakeCStr(''));
    END
    ELSE
    BEGIN
      AbortWith2('codegen: assignment type mismatch for: ', ctx_name);
      CoerceForAssign := v;
    END;
  END
  ELSE IF IsIntegerFamilyTk(from_tid) AND IsIntegerFamilyTk(to_tid) THEN
  BEGIN
    { General integer-family narrow/widen, matching the reference's
      _coerce_assign_value: any two integer-family scalars coerce purely by
      LLVM width regardless of TypesCompatibleForAssign's stricter
      same-tid/WORD-widening rule -- e.g. INTEGER32 -> INTEGER (a plain
      truncation, used by lexer.pas's radix-literal scan accumulator). }
    IF IntFamilyWidth(from_tid) > IntFamilyWidth(to_tid) THEN
      CoerceForAssign := LLVMBuildTrunc(builder, v, LLVMTypeForTk(to_tid), MakeCStr(''))
    ELSE IF IsUnsignedWordTk(from_tid) THEN
      CoerceForAssign := LLVMBuildZExt(builder, v, LLVMTypeForTk(to_tid), MakeCStr(''))
    ELSE
      CoerceForAssign := LLVMBuildSExt(builder, v, LLVMTypeForTk(to_tid), MakeCStr(''));
  END
  ELSE
  BEGIN
    AbortWith2('codegen: assignment type mismatch for: ', ctx_name);
    CoerceForAssign := v;
  END;
END;

FUNCTION RoundUpBytes(n, a: INTEGER32): INTEGER32;
{ Round n up to the next multiple of alignment a, matching the reference's
  c_abi.py::_round_up -- shared by TypeSizeBytes/TypeAlignBytes's struct
  layout below. }
BEGIN
  RoundUpBytes := ((n + a - 1) DIV a) * a;
END;

FUNCTION TypeAlignBytes(tid: INTEGER): INTEGER32;
{ Natural (non-packed) byte alignment of a Pascal type's LLVM representation
  -- mirrors the reference's c_abi.py::_align_of exactly (scalars align to
  their width, ARRAY/RECORD take their element/field max), since
  CodegenTypeDecl builds RECORD as an ordinary is_packed=0 LLVMStructType
  (natural C-like layout with padding), not a byte-packed one. TypeSizeBytes
  below depends on this agreeing with the real LLVM layout, or its
  pointer-arithmetic callers (NEW-style malloc sizing, array-of-record
  indexing) silently drift out of step with the actual field offsets LLVM's
  GEP computes -- found via a real bug this way: a Token record mixing
  Str255/INTEGER32 fields with a REAL field (needing 8-byte alignment)
  computed too small a stride, corrupting the heap one record at a time
  until a later, unrelated allocation crashed. }
VAR
  i: INTEGER;
  best, fa: INTEGER32;
BEGIN
  IF tid = TK_INTEGER THEN TypeAlignBytes := 2
  ELSE IF tid = TK_WORD THEN TypeAlignBytes := 2
  ELSE IF tid = TK_INTEGER8 THEN TypeAlignBytes := 1
  ELSE IF tid = TK_WORD8 THEN TypeAlignBytes := 1
  ELSE IF tid = TK_BOOLEAN THEN TypeAlignBytes := 1
  ELSE IF tid = TK_CHAR THEN TypeAlignBytes := 1
  ELSE IF tid = TK_INTEGER32 THEN TypeAlignBytes := 4
  ELSE IF tid = TK_WORD32 THEN TypeAlignBytes := 4
  ELSE IF tid = TK_REAL32 THEN TypeAlignBytes := 4
  ELSE IF tid = TK_INTEGER64 THEN TypeAlignBytes := 8
  ELSE IF tid = TK_WORD64 THEN TypeAlignBytes := 8
  ELSE IF tid = TK_REAL THEN TypeAlignBytes := 8
  ELSE IF tid = TK_ADRMEM THEN TypeAlignBytes := 8
  ELSE IF TypeKind(tid) = TK_POINTER THEN TypeAlignBytes := 8
  ELSE IF TypeKind(tid) = TK_ARRAY THEN TypeAlignBytes := TypeAlignBytes(types[tid].elem_tid)
  ELSE IF TypeKind(tid) = TK_RECORD THEN
  BEGIN
    best := 1;
    FOR i := 1 TO nfields DO
      IF fields[i].rec_tid = tid THEN
      BEGIN
        fa := TypeAlignBytes(fields[i].field_tid);
        IF fa > best THEN best := fa;
      END;
    TypeAlignBytes := best;
  END
  ELSE IF TypeKind(tid) = TK_LSTRING THEN TypeAlignBytes := 1
  ELSE IF TypeKind(tid) = TK_STRING THEN TypeAlignBytes := 1
  ELSE IF TypeKind(tid) = TK_SET THEN TypeAlignBytes := 8
  ELSE IF TypeKind(tid) = TK_VECTOR THEN
  BEGIN
    { LLVM's natural vector ABI alignment: the total size rounded up to a
      power of two, with no upper cap. The x86-64 datalayout carries no `v`
      spec, so LLVM falls back to PowerOf2Ceil(size) for every vector width;
      confirmed against clang x86-64 _Alignof for the whole legal range --
      the small totals (<2 x i8>=2, <4 x i8>=4, <8 x i32>=32) and the
      largest legal vectors alike (VECTOR [64] OF INTEGER64 = 512 bytes ->
      align 512, VECTOR [64] OF INTEGER32 = 256 -> 256). Since lane count
      and element size are both powers of two their product already is one,
      so the round-up loop below is a no-op in practice; it stays as a
      guard. The total is rebuilt from the ELEMENT's alignment rather than
      a TypeSizeBytes call: every
      scalar's size equals its alignment, and same-unit calls resolve in
      implementation order under the reference compiler, which
      TypeSizeBytes's implementation follows this one's (its ARRAY arm
      calling TypeAlignBytes is the allowed direction). The checklit
      vector_types fixture pins this against the emitted alloca text. }
    best := TypeAlignBytes(types[tid].elem_tid) * (types[tid].hi - types[tid].lo + 1);
    fa := 1;
    WHILE fa < best DO fa := fa * 2;
    TypeAlignBytes := fa;
  END
  ELSE
  BEGIN
    AbortWith('codegen: TypeAlignBytes: unsupported type');
    TypeAlignBytes := 1;
  END;
END;

FUNCTION TypeSizeBytes(tid: INTEGER): INTEGER32;
{ Used by SIZEOF and NEW's malloc-sized allocation -- must agree exactly
  with the real (natural-alignment) LLVM layout CodegenTypeDecl builds, so
  ARRAY-of-RECORD pointer arithmetic (base + i * SIZEOF(rec)) lands on the
  same offsets GEP does; see TypeAlignBytes above for why a naive
  no-padding sum is wrong. }
VAR
  i: INTEGER;
  off, fa, end_off: INTEGER32;
BEGIN
  IF tid = TK_INTEGER THEN TypeSizeBytes := 2
  ELSE IF tid = TK_REAL THEN TypeSizeBytes := 8
  ELSE IF tid = TK_BOOLEAN THEN TypeSizeBytes := 1
  ELSE IF tid = TK_CHAR THEN TypeSizeBytes := 1
  ELSE IF tid = TK_WORD THEN TypeSizeBytes := 2
  ELSE IF tid = TK_INTEGER8 THEN TypeSizeBytes := 1
  ELSE IF tid = TK_WORD8 THEN TypeSizeBytes := 1
  ELSE IF tid = TK_INTEGER32 THEN TypeSizeBytes := 4
  ELSE IF tid = TK_WORD32 THEN TypeSizeBytes := 4
  ELSE IF tid = TK_INTEGER64 THEN TypeSizeBytes := 8
  ELSE IF tid = TK_WORD64 THEN TypeSizeBytes := 8
  ELSE IF tid = TK_REAL32 THEN TypeSizeBytes := 4
  ELSE IF tid = TK_ADRMEM THEN TypeSizeBytes := 8
  ELSE IF TypeKind(tid) = TK_ARRAY THEN
    TypeSizeBytes := RoundUpBytes(TypeSizeBytes(types[tid].elem_tid), TypeAlignBytes(types[tid].elem_tid))
                      * (types[tid].hi - types[tid].lo + 1)
  ELSE IF TypeKind(tid) = TK_RECORD THEN
  BEGIN
    end_off := 0;
    FOR i := 1 TO nfields DO
      IF fields[i].rec_tid = tid THEN
      BEGIN
        off := fields[i].byte_offset + TypeSizeBytes(fields[i].field_tid);
        IF off > end_off THEN end_off := off;
      END;
    TypeSizeBytes := RoundUpBytes(end_off, TypeAlignBytes(tid));
  END
  ELSE IF TypeKind(tid) = TK_LSTRING THEN TypeSizeBytes := types[tid].hi + 1
  ELSE IF TypeKind(tid) = TK_STRING THEN TypeSizeBytes := types[tid].hi
  ELSE IF TypeKind(tid) = TK_SET THEN TypeSizeBytes := 32
  ELSE IF TypeKind(tid) = TK_POINTER THEN TypeSizeBytes := 8
  ELSE IF TypeKind(tid) = TK_VECTOR THEN
    { Vector lanes are packed -- no inter-lane padding, unlike an ARRAY's
      RoundUpBytes stride -- so the size is exactly element-size * lanes.
      Every legal element size is a power of two, so the ARRAY formula
      would give the same answer; this spelling documents the intent. }
    TypeSizeBytes := TypeSizeBytes(types[tid].elem_tid) * (types[tid].hi - types[tid].lo + 1)
  ELSE
  BEGIN
    AbortWith('codegen: TypeSizeBytes: unsupported type');
    TypeSizeBytes := 0;
  END;
END;

FUNCTION IsAggregateTk(tk: INTEGER): BOOLEAN;
{ The types that cross the C ABI as aggregates rather than as single
  machine values -- exactly the set FlattenParams marks needs_copy for, kept
  as one named predicate so the parameter side and the RETURN side (which
  has no needs_copy flag of its own) can never drift apart. }
BEGIN
  IsAggregateTk := (TypeKind(tk) = TK_ARRAY) OR (TypeKind(tk) = TK_RECORD) OR
                   (TypeKind(tk) = TK_LSTRING) OR (TypeKind(tk) = TK_STRING) OR
                   (TypeKind(tk) = TK_VECTOR);
END;

FUNCTION SysVMergeClass(a: INTEGER; b: INTEGER): INTEGER;
{ The System V AMD64 class-merge lattice. }
BEGIN
  IF a = b THEN SysVMergeClass := a
  ELSE IF a = SYSV_EB_NONE THEN SysVMergeClass := b
  ELSE IF b = SYSV_EB_NONE THEN SysVMergeClass := a
  ELSE IF (a = SYSV_EB_MEMORY) OR (b = SYSV_EB_MEMORY) THEN SysVMergeClass := SYSV_EB_MEMORY
  ELSE IF (a = SYSV_EB_INTEGER) OR (b = SYSV_EB_INTEGER) THEN SysVMergeClass := SYSV_EB_INTEGER
  ELSE SysVMergeClass := SYSV_EB_SSE;
END;

FUNCTION IsSysVLeafTid(tid: INTEGER): BOOLEAN;
{ TRUE for exactly the scalar types TypeSizeBytes/TypeAlignBytes handle
  without recursing -- the leaves of the walk below. }
BEGIN
  IsSysVLeafTid := (tid = TK_INTEGER) OR (tid = TK_WORD) OR (tid = TK_INTEGER8)
                OR (tid = TK_WORD8) OR (tid = TK_BOOLEAN) OR (tid = TK_CHAR)
                OR (tid = TK_INTEGER32) OR (tid = TK_WORD32) OR (tid = TK_REAL32)
                OR (tid = TK_INTEGER64) OR (tid = TK_WORD64) OR (tid = TK_REAL)
                OR (tid = TK_ADRMEM) OR (TypeKind(tid) = TK_POINTER);
END;

PROCEDURE WalkTypeLeaves(tid: INTEGER; base_off: INTEGER32; VAR nleaves: INTEGER32;
                          VAR leaf_off: SysVLeafOffArr; VAR leaf_tid: SysVLeafTidArr);
{ Append (absolute byte offset, scalar leaf tid) for every scalar leaf of tid
  to the caller's arrays, recursing through RECORD fields and ARRAY elements.
  Pascal has no generators, so the flat result is accumulated into fixed-size
  VAR arrays instead of being yielded lazily. RECORD field offsets come
  straight from fields[].byte_offset (already the natural-alignment layout);
  ARRAY elements use the same stride TypeSizeBytes uses for the array's own
  size, so the two can never disagree. }
VAR
  i: INTEGER;
  stride: INTEGER32;
  k, n: INTEGER32;
BEGIN
  IF IsSysVLeafTid(tid) THEN
  BEGIN
    IF nleaves >= MAX_SYSV_LEAVES THEN
      AbortWith('codegen: WalkTypeLeaves: too many scalar leaves in aggregate');
    nleaves := nleaves + 1;
    leaf_off[nleaves] := base_off;
    leaf_tid[nleaves] := tid;
  END
  ELSE IF TypeKind(tid) = TK_ARRAY THEN
  BEGIN
    stride := RoundUpBytes(TypeSizeBytes(types[tid].elem_tid), TypeAlignBytes(types[tid].elem_tid));
    n := types[tid].hi - types[tid].lo + 1;
    FOR k := 0 TO n - 1 DO
      WalkTypeLeaves(types[tid].elem_tid, base_off + k * stride, nleaves, leaf_off, leaf_tid);
  END
  ELSE IF TypeKind(tid) = TK_RECORD THEN
  BEGIN
    FOR i := 1 TO nfields DO
      IF fields[i].rec_tid = tid THEN
        WalkTypeLeaves(fields[i].field_tid, base_off + fields[i].byte_offset,
                       nleaves, leaf_off, leaf_tid);
  END
  ELSE
    AbortWith('codegen: WalkTypeLeaves: unsupported type in C aggregate');
END;

FUNCTION AggregateHasVectorLeaf(tid: INTEGER): BOOLEAN;
{ TRUE if tid is a VECTOR, or transitively contains one through ARRAY
  elements or RECORD fields. ClassifyAggregate uses this to force the whole
  enclosing aggregate to MEMORY class: vector-register ABI classes (SSEUP)
  are not implemented, and WalkTypeLeaves has no vector arm, so a small
  (<= 16 byte) aggregate wrapping a vector would otherwise reach the
  WalkTypeLeaves internal-error above. Same recursion shape as
  WalkTypeLeaves, implemented ahead of it in file order. }
VAR
  i: INTEGER;
  found: BOOLEAN;
BEGIN
  IF TypeKind(tid) = TK_VECTOR THEN
    AggregateHasVectorLeaf := TRUE
  ELSE IF TypeKind(tid) = TK_ARRAY THEN
    AggregateHasVectorLeaf := AggregateHasVectorLeaf(types[tid].elem_tid)
  ELSE IF TypeKind(tid) = TK_RECORD THEN
  BEGIN
    found := FALSE;
    FOR i := 1 TO nfields DO
      IF fields[i].rec_tid = tid THEN
        IF AggregateHasVectorLeaf(fields[i].field_tid) THEN found := TRUE;
    AggregateHasVectorLeaf := found;
  END
  ELSE
    AggregateHasVectorLeaf := FALSE;
END;

PROCEDURE ClassifyAggregate(tk: INTEGER; VAR agg_class: INTEGER; VAR n_pieces: INTEGER;
                             VAR piece_kind: SysVPieceArr; VAR piece_bytes: SysVPieceSzArr);
{ The full System V AMD64 aggregate classifier. NVPTX currently also uses this
  host classifier and produces correct, host-shaped parameter buffers. Any
  device-specific aggregate lowering must branch on is_nvptx_device at the
  cg_decl and cg_expr call sites, not inside this classifier.

  Splits an aggregate of at most 16 bytes into one or two eightbytes, merges
  every scalar leaf's class into
  the eightbyte it lands in, and reports either MEMORY (passed in memory) or
  COERCED plus the register piece each eightbyte is passed in.

  Worked examples (byte offsets / eightbyte index / merged class):
    RECORD a, b: INTEGER32 END -- size 8, leaves 0:i32, 4:i32, both eightbyte
      0, INTEGER+INTEGER = INTEGER, end = 8 -> COERCED, 1 integer piece of
      8 bytes.
    RECORD a: REAL END -- size 8, leaf 0:REAL -> eightbyte 0 SSE with a
      double leaf -> COERCED, 1 double piece.
    RECORD a, b: REAL32 END -- size 8, leaves 0:f32, 4:f32 -> eightbyte 0 SSE,
      no double, sse_end 8 > 4 -> COERCED, 1 two-float-vector piece.
    ARRAY [1..3] OF INTEGER32 -- size 12, leaves 0, 4, 8; eightbyte 0 gets
      offsets 0 and 4 (end 8, used 8), eightbyte 1 gets offset 8 (end 12,
      used 4) -> COERCED, pieces integer/8 bytes and integer/4 bytes.
    Anything over 16 bytes, or of size 0 -> MEMORY, no pieces. }
VAR
  size, used: INTEGER32;
  nleaves, li, lsz, lend: INTEGER32;
  leaf_off: SysVLeafOffArr;
  leaf_tid: SysVLeafTidArr;
  eb, n_eb, leaf_cls, i: INTEGER;
  cls: SysVPieceArr;
  eb_end: SysVPieceSzArr;
  sse_end: SysVPieceSzArr;
  sse_dbl: SysVFlagArr;
BEGIN
  n_pieces := 0;
  IF AggregateHasVectorLeaf(tk) THEN
  BEGIN
    { Vector-register ABI classes (SSEUP) are not implemented, so any
      aggregate that is a vector -- or contains one through a field or
      element -- is forced MEMORY-class. A bare VECTOR in a [C] routine
      signature is rejected before this runs (see cg_decl); this arm covers
      a vector nested inside a [C] record/ARRAY parameter, where classifying
      the whole aggregate MEMORY is both the correct answer and the only
      shape WalkTypeLeaves (which has no vector arm) can handle. }
    agg_class := SYSV_CLASS_MEMORY;
    RETURN;
  END;
  size := TypeSizeBytes(tk);
  IF (size = 0) OR (size > 16) THEN
  BEGIN
    agg_class := SYSV_CLASS_MEMORY;
    RETURN;
  END;

  { (size + 7) DIV 8, spelled out so the eightbyte index stays a plain
    INTEGER rather than an INTEGER32: size is at most 16 here. }
  IF size > 8 THEN n_eb := 2 ELSE n_eb := 1;
  FOR i := 1 TO 2 DO
  BEGIN
    cls[i] := SYSV_EB_NONE;
    eb_end[i] := 0;
    sse_end[i] := 0;
    sse_dbl[i] := FALSE;
  END;

  nleaves := 0;
  WalkTypeLeaves(tk, 0, nleaves, leaf_off, leaf_tid);

  FOR li := 1 TO nleaves DO
  BEGIN
    lsz := TypeSizeBytes(leaf_tid[li]);
    { Eightbyte index, 1-based here (the reference's 0-based off DIV 8). A
      leaf can only land past the second eightbyte in a malformed layout, and
      such a leaf is skipped, exactly as the reference skips eb >= n_eb. }
    IF leaf_off[li] >= 8 THEN eb := 2 ELSE eb := 1;
    IF (eb <= n_eb) AND (leaf_off[li] < 16) THEN
    BEGIN
      IF (leaf_tid[li] = TK_REAL) OR (leaf_tid[li] = TK_REAL32) THEN
        leaf_cls := SYSV_EB_SSE
      ELSE
        leaf_cls := SYSV_EB_INTEGER;
      cls[eb] := SysVMergeClass(cls[eb], leaf_cls);
      { Last occupied byte within this eightbyte, clamped to its end. }
      lend := leaf_off[li] + lsz;
      IF lend > eb * 8 THEN lend := eb * 8;
      IF lend > eb_end[eb] THEN eb_end[eb] := lend;
      IF leaf_cls = SYSV_EB_SSE THEN
      BEGIN
        IF lend > sse_end[eb] THEN sse_end[eb] := lend;
        IF leaf_tid[li] = TK_REAL THEN sse_dbl[eb] := TRUE;
      END;
    END;
  END;

  FOR eb := 1 TO n_eb DO
    IF cls[eb] = SYSV_EB_MEMORY THEN
    BEGIN
      agg_class := SYSV_CLASS_MEMORY;
      n_pieces := 0;
      RETURN;
    END;

  agg_class := SYSV_CLASS_COERCED;
  n_pieces := n_eb;
  FOR eb := 1 TO n_eb DO
  BEGIN
    used := eb_end[eb] - (eb - 1) * 8;
    IF cls[eb] = SYSV_EB_SSE THEN
    BEGIN
      IF sse_dbl[eb] THEN
      BEGIN
        piece_kind[eb] := SYSV_PIECE_DOUBLE;
        piece_bytes[eb] := 8;
      END
      ELSE IF (sse_end[eb] - (eb - 1) * 8) > 4 THEN
      BEGIN
        piece_kind[eb] := SYSV_PIECE_SSEVEC;
        piece_bytes[eb] := 8;
      END
      ELSE
      BEGIN
        piece_kind[eb] := SYSV_PIECE_FLOAT;
        piece_bytes[eb] := 4;
      END;
    END
    ELSE
    BEGIN
      { INTEGER, and also the INTEGER+SSE merge result. The reference builds
        an integer of max(8, used * 8) *bits*, i.e. at least one byte wide;
        the equivalent byte width is what is reported here. }
      piece_kind[eb] := SYSV_PIECE_INTEGER;
      IF used > 1 THEN piece_bytes[eb] := used ELSE piece_bytes[eb] := 1;
    END;
  END;
END;

FUNCTION SysVAggClass(tk: INTEGER): INTEGER;
{ Memory-vs-register answer only, for callers that do not need the per-piece
  breakdown ClassifyAggregate reports. Returns plain INTEGER (not INTEGER32),
  matching TypeKind's own return type -- the native typechecker's
  CheckExpr/IsNumeric treats INTEGER and INTEGER32 as distinct,
  non-interchangeable comparison operand kinds, and every caller here
  compares the result against an INTEGER-typed CONST (SYSV_CLASS_MEMORY /
  SYSV_CLASS_COERCED). }
VAR
  agg_class, n_pieces: INTEGER;
  piece_kind: SysVPieceArr;
  piece_bytes: SysVPieceSzArr;
BEGIN
  ClassifyAggregate(tk, agg_class, n_pieces, piece_kind, piece_bytes);
  SysVAggClass := agg_class;
END;

FUNCTION SysVByvalAlign(tk: INTEGER): INTEGER32;
{ The `align` attribute a MEMORY-class aggregate's byval/sret pointer needs.
  SysV AMD64 passes MEMORY-class arguments in eightbyte-granular stack slots
  regardless of the aggregate's own natural alignment, so clang always emits
  at least align 8 for byval/sret even when TypeAlignBytes reports less (a
  RECORD of only INTEGER32 fields naturally aligns to 4, but still lands on
  an 8-byte-aligned stack slot) -- found by a clang spot-check diverging from
  this compiler's earlier align-4 output for exactly such a RECORD. }
BEGIN
  IF TypeAlignBytes(tk) > 8 THEN SysVByvalAlign := TypeAlignBytes(tk)
  ELSE SysVByvalAlign := 8;
END;

FUNCTION SysVPieceLLVMType(kind: INTEGER; nbytes: INTEGER32): ADRMEM;
{ The LLVM type one COERCED eightbyte is passed in, from the piece kind and
  byte width ClassifyAggregate reports (nbytes is meaningful only for the
  integer kind; the others have their width implied). }
BEGIN
  IF kind = SYSV_PIECE_DOUBLE THEN SysVPieceLLVMType := dblty
  ELSE IF kind = SYSV_PIECE_FLOAT THEN SysVPieceLLVMType := f32ty
  ELSE IF kind = SYSV_PIECE_SSEVEC THEN SysVPieceLLVMType := LLVMVectorType(f32ty, 2)
  ELSE SysVPieceLLVMType := LLVMIntTypeInContext(ctx, nbytes * 8);
END;

FUNCTION SysVCoercedStructType(n_pieces: INTEGER; VAR piece_kind: SysVPieceArr;
                                VAR piece_bytes: SysVPieceSzArr): ADRMEM;
{ The literal struct of an aggregate's register pieces, laid over the
  aggregate's own storage so each piece can be loaded/stored at its
  eightbyte offset (the reference's AggInfo.coerced_struct). Always a
  struct, even for a single piece: a one-element struct GEPs the same way a
  two-element one does, which keeps the piece loops below single-shaped. }
VAR
  elem_tys: ADRMEM;
  eb: INTEGER;
BEGIN
  elem_tys := AllocPtrArray(n_pieces);
  FOR eb := 1 TO n_pieces DO
    SetPtrArrayElem(elem_tys, eb - 1, SysVPieceLLVMType(piece_kind[eb], piece_bytes[eb]));
  SysVCoercedStructType := LLVMStructTypeInContext(ctx, elem_tys, n_pieces, 0);
END;

FUNCTION SysVCoercedRetType(n_pieces: INTEGER; VAR piece_kind: SysVPieceArr;
                             VAR piece_bytes: SysVPieceSzArr): ADRMEM;
{ The LLVM return type of a COERCED-class aggregate return: the bare piece
  type when the aggregate occupies a single eightbyte, otherwise the literal
  struct of both pieces -- mirroring the reference's
  `pcs[0] if len(pcs) == 1 else ret_agg.coerced_struct()`. Note this differs
  from the parameter side, which always spreads the pieces into separate
  parameters; a function has only one return slot to spend. }
BEGIN
  IF n_pieces = 1 THEN
    SysVCoercedRetType := SysVPieceLLVMType(piece_kind[1], piece_bytes[1])
  ELSE
    SysVCoercedRetType := SysVCoercedStructType(n_pieces, piece_kind, piece_bytes);
END;

FUNCTION SysVCoercedPiecePtr(base: ADRMEM; cstruct_ty: ADRMEM; eb: INTEGER): ADRMEM;
{ Address of COERCED piece `eb` (1-based) within storage `base` already
  bitcast to a pointer to cstruct_ty. }
VAR
  gep_idx: ADRMEM;
BEGIN
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, eb - 1, 0));
  SysVCoercedPiecePtr := LLVMBuildGEP2(builder, cstruct_ty, base, gep_idx, 2, MakeCStr(''));
END;

{ Vintage array bounds can be INTEGER or WORD constants. Keep the widened
  value until both bounds are known; ResolveTypeExpr then applies the manual's
  negative-INTEGER-to-WORD adaptation when one bound selects WORD. }
FUNCTION CheckedIndexBound(wide: INTEGER64): INTEGER32;
BEGIN
  IF (wide > MAXWORD) OR (wide < -32767) THEN
  BEGIN
    AbortWith('codegen: array index bound is outside -32767..65535');
    CheckedIndexBound := 0;
  END
  ELSE
    CheckedIndexBound := RETYPE(INTEGER32, wide);
END;

FUNCTION ResolveIntLiteral(node: ADRMEM): INTEGER32;
{ An array index bound is a full constant-expression AST node (the parser
  never unwraps it the way it does e.g. NamedType.param) -- so reading it
  needs to drill into the node's own 'value' field, not treat the node
  itself as a bare JSON number. Also resolves a bare Identifier bound
  through the CONST table (e.g. "ARRAY [1..MAX_SYMBOLS]"), pervasive in
  this repository's own native sources; any other computed bound expression
  is still not supported. }
VAR
  nm: Str255;
  ci: INTEGER32;
  wide: INTEGER64;
BEGIN
  IF NodeType(node) = 'IntLiteral' THEN
    ResolveIntLiteral := CheckedIndexBound(RETYPE(INTEGER64, GetInt(node, 'value')))
  ELSE IF NodeType(node) = 'Identifier' THEN
  BEGIN
    nm := GetStr(node, 'name');
    ci := LookupConst(nm);
    IF ci = 0 THEN
    BEGIN
      AbortWith2('codegen: undefined constant in array index bound: ', nm);
      ResolveIntLiteral := 0;
    END
    ELSE
    BEGIN
      wide := const_tbl[ci].ival;
      ResolveIntLiteral := CheckedIndexBound(wide);
    END;
  END
  ELSE
  BEGIN
    AbortWith('codegen: array index bounds must be integer literals or CONST identifiers');
    ResolveIntLiteral := 0;
  END;
END;

FUNCTION TypeNameStrToTk(nm: Str255): INTEGER;
{ Maps a RetypeExpr node's bare type_id string (e.g. 'INTEGER') to a tk.
  Only the scalar integer-family names RETYPE is actually used with across
  the self-hosting sources are covered -- unlike ResolveTypeExpr (which
  resolves a full TypeExpr AST node and also handles STRING/records/etc),
  this only needs to answer "what integer width is this". }
VAR
  tid: INTEGER;
  unm: Str255;
BEGIN
  unm := UpperStr(nm);
  IF ((unm = 'INTEGER8') OR (unm = 'INTEGER16') OR (unm = 'INTEGER32') OR
      (unm = 'INTEGER64') OR (unm = 'WORD8') OR (unm = 'WORD16') OR
      (unm = 'WORD32') OR (unm = 'WORD64')) AND
     (NOT (active_features.wide_integers OR is_device_compiland)) THEN
    AbortWith2('codegen: type requires the extended dialect: ', nm);
  IF ((unm = 'CSHORT') OR (unm = 'CINT') OR (unm = 'CLONG') OR
      (unm = 'CSIZE_T')) AND (NOT FeaturesAreExtended(active_features)) THEN
    AbortWith2('codegen: type requires the extended dialect: ', nm);
  IF unm = 'INTEGER' THEN tid := TK_INTEGER
  ELSE IF unm = 'INTEGER16' THEN tid := TK_INTEGER
  ELSE IF unm = 'WORD' THEN tid := TK_WORD
  ELSE IF unm = 'WORD16' THEN tid := TK_WORD
  ELSE IF unm = 'INTEGER8' THEN tid := TK_INTEGER8
  ELSE IF unm = 'WORD8' THEN tid := TK_WORD8
  ELSE IF unm = 'INTEGER32' THEN tid := TK_INTEGER32
  ELSE IF unm = 'WORD32' THEN tid := TK_WORD32
  ELSE IF unm = 'INTEGER64' THEN tid := TK_INTEGER64
  ELSE IF unm = 'WORD64' THEN tid := TK_WORD64
  ELSE IF unm = 'CSHORT' THEN tid := TK_INTEGER
  ELSE IF unm = 'CINT' THEN tid := TK_INTEGER32
  ELSE IF (unm = 'CLONG') OR (unm = 'CSIZE_T') THEN tid := TK_INTEGER64
  ELSE
  BEGIN
    AbortWith2('codegen: RETYPE target type not supported: ', nm);
    tid := 0;
  END;
  TypeNameStrToTk := tid;
END;

FUNCTION ResolveTypeExpr(te: ADRMEM): INTEGER;
VAR
  nm, unm, flavor, space_name: Str255;
  nt: Str255;
  tid: INTEGER;
  elem_tid, space_code: INTEGER;
  lo, hi: INTEGER32;
  count: INTEGER32;
  arr_ty: ADRMEM;
  fields_arr, field_tuple, items, fnames_arr, ftype_expr: ADRMEM;
  variants_arr, arm_node, tag_type_expr: ADRMEM;
  fn2: INTEGER;
  nfd, fi, fni, ai: INTEGER32;
  pow2: INTEGER32;
  field_tid, tag_tid: INTEGER;
  payload_align, payload_size, arm_off, fixed_off: INTEGER32;
  fname: Str255;
  elem_llvm_types: ADRMEM;
  struct_ty, payload_ty: ADRMEM;
  field_index: INTEGER;
  has_variants: BOOLEAN;
  values_arr: ADRMEM; { EnumType's member identifier list }
  mi: INTEGER32;
  named_tid: INTEGER;
BEGIN
  nt := NodeType(te);
  IF nt = 'NamedType' THEN
  BEGIN
    nm := GetStr(te, 'name');
    unm := UpperStr(nm);
    { A user TYPE of this name wins over the predeclared meaning. IBM Pascal,
      Aug 1981, p.3-7: predeclared identifiers "can be re-defined by the
      programmer, but doing this is not recommended" -- and none of them is a
      reserved word, the contrast the manual draws for NIL. The compiler's own
      internal uses of the built-in meaning are unaffected (p.6228, on
      BOOLEAN: "the old type is implicitly used by the compiler for things
      like the IF statement"). Matches the reference's resolve_type.

      STRING(n) and LSTRING(n) arrive as NamedTypes carrying a param and are
      built-in string constructors, never the shadowing user type, so they
      skip this probe. }
    named_tid := 0;
    IF GetObjOrNil(te, 'param') = NIL THEN named_tid := LookupNamedType(nm);
    IF named_tid <> 0 THEN tid := named_tid
    ELSE IF unm = 'INTEGER' THEN tid := TK_INTEGER
    ELSE IF unm = 'REAL' THEN tid := TK_REAL
    ELSE IF unm = 'BOOLEAN' THEN tid := TK_BOOLEAN
    ELSE IF unm = 'CHAR' THEN tid := TK_CHAR
    ELSE IF unm = 'WORD' THEN tid := TK_WORD
    ELSE IF (unm = 'INTEGER8') OR (unm = 'INTEGER16') OR (unm = 'INTEGER32') OR
            (unm = 'INTEGER64') OR (unm = 'WORD8') OR (unm = 'WORD16') OR
            (unm = 'WORD32') OR (unm = 'WORD64') THEN
    BEGIN
      IF NOT (active_features.wide_integers OR is_device_compiland) THEN
        AbortWith2('codegen: type requires the extended dialect: ', nm);
      IF unm = 'INTEGER8' THEN tid := TK_INTEGER8
      ELSE IF unm = 'INTEGER16' THEN tid := TK_INTEGER
      ELSE IF unm = 'INTEGER32' THEN tid := TK_INTEGER32
      ELSE IF unm = 'INTEGER64' THEN tid := TK_INTEGER64
      ELSE IF unm = 'WORD8' THEN tid := TK_WORD8
      ELSE IF unm = 'WORD16' THEN tid := TK_WORD
      ELSE IF unm = 'WORD32' THEN tid := TK_WORD32
      ELSE tid := TK_WORD64;
    END
    ELSE IF (unm = 'REAL32') OR (unm = 'REAL64') THEN
    BEGIN
      IF NOT (active_features.wide_reals OR is_device_compiland) THEN
        AbortWith2('codegen: type requires the extended dialect: ', nm);
      IF unm = 'REAL32' THEN tid := TK_REAL32
      ELSE tid := TK_REAL;
    END
    ELSE IF (unm = 'ADRMEM') OR (unm = 'ADSMEM') THEN tid := TK_ADRMEM
    { C-ABI fixed-width aliases for [C]; EXTERN declarations. }
    ELSE IF (unm = 'CPTR') OR (unm = 'CCHAR') OR (unm = 'CSHORT') OR
            (unm = 'CINT') OR (unm = 'CLONG') OR (unm = 'CSIZE_T') OR
            (unm = 'CDOUBLE') THEN
    BEGIN
      IF NOT FeaturesAreExtended(active_features) THEN
        AbortWith2('codegen: type requires the extended dialect: ', nm);
      IF unm = 'CPTR' THEN tid := TK_ADRMEM
      ELSE IF unm = 'CCHAR' THEN tid := TK_CHAR
      ELSE IF unm = 'CSHORT' THEN tid := TK_INTEGER
      ELSE IF unm = 'CINT' THEN tid := TK_INTEGER32
      ELSE IF (unm = 'CLONG') OR (unm = 'CSIZE_T') THEN tid := TK_INTEGER64
      ELSE tid := TK_REAL;
    END
    ELSE IF unm = 'TEXT' THEN
      tid := RegisterType(TK_FILE, TK_CHAR, 0, 1, i8ptrty)
    ELSE IF unm = 'LSTRING' THEN
    BEGIN
      { A bare LSTRING is LSTRING(256), the same default STRING takes below --
        the reference resolves it that way. Reaching here at all means no user
        TYPE of the name shadowed it: the probe above only skips a NamedType
        carrying a param. }
      IF GetObjOrNil(te, 'param') = NIL THEN hi := 256
      ELSE hi := ORD(GetInt(te, 'param'));
      arr_ty := LLVMArrayType(i8ty, hi + 1);
      tid := RegisterType(TK_LSTRING, TK_CHAR, 0, hi, arr_ty);
    END
    ELSE IF unm = 'STRING' THEN
    BEGIN
      IF GetObjOrNil(te, 'param') = NIL THEN hi := 256
      ELSE hi := ORD(GetInt(te, 'param'));
      arr_ty := LLVMArrayType(i8ty, hi);
      tid := RegisterType(TK_STRING, TK_CHAR, 1, hi, arr_ty);
    END
    ELSE
    BEGIN
      { Unparameterised names were already probed above; a NamedType carrying
        a param that is not STRING(n) still has to resolve by name. }
      tid := LookupNamedType(nm);
      IF tid = 0 THEN
      BEGIN
        AbortWith2('codegen: unsupported or undeclared type: ', nm);
        tid := TK_UNKNOWN;
      END;
    END;
  END
  ELSE IF nt = 'ArrayType' THEN
  BEGIN
    IF GetBool(te, 'packed') THEN
      AbortWith('codegen: PACKED arrays are not supported');
    lo := ResolveIntLiteral(GetObj(GetObj(te, 'index_range'), 'low'));
    elem_tid := ResolveTypeExpr(GetObj(te, 'element_type'));
    IF GetBool(te, 'super') THEN
    BEGIN
      { A SUPER ARRAY has no physical aggregate header or upper bound. Its
        representation is its element type, so ADS OF SUPER ARRAY becomes a
        flat element pointer and c^[i] can use a one-index GEP. }
      tid := RegisterType(TK_ARRAY, elem_tid, lo, lo, LLVMTypeForTk(elem_tid));
      types[tid].is_super := TRUE;
    END
    ELSE
    BEGIN
      hi := ResolveIntLiteral(GetObj(GetObj(te, 'index_range'), 'high'));
      IF (lo < 0) AND (hi > MAXINT) THEN lo := lo + MAXINT + 1 + MAXINT + 1;
      IF (hi < 0) AND (lo > MAXINT) THEN hi := hi + MAXINT + 1 + MAXINT + 1;
      IF lo > hi THEN AbortWith('codegen: invalid array index range');
      count := hi - lo + 1;
      arr_ty := LLVMArrayType(LLVMTypeForTk(elem_tid), count);
      tid := RegisterType(TK_ARRAY, elem_tid, lo, hi, arr_ty);
    END;
  END
  ELSE IF nt = 'VectorType' THEN
  BEGIN
    RejectNvptxVector;
    IF GetBool(te, 'packed') THEN
      AbortWith('codegen: PACKED vectors are not supported');
    { Lane count and element kind are re-validated here, mirroring the
      typechecker's VectorType rules exactly: this file also resolves type
      expressions that never crossed a typechecker (frozen-AST .check
      inputs, sizeof_synth synthesis), so the rules cannot be skipped.
      Bare scalar tids are 1..13; 1..12 is the vector-element family
      (TK_INTEGER..TK_REAL32), which also rejects pointers/ADRMEM and
      every registered aggregate tid by construction. }
    { ResolveIntLiteral itself aborts on any node that is not an integer
      literal or a CONST identifier, but with an array-flavoured message;
      pre-check the shape here so the diagnostic names the vector lane
      count. Mirrors the typechecker's VectorType arm. }
    IF (NodeType(GetObj(te, 'lanes')) <> 'IntLiteral') AND
       (NodeType(GetObj(te, 'lanes')) <> 'Identifier') THEN
      AbortWith('codegen: vector lane count must be an integer literal or a CONST integer identifier');
    count := ResolveIntLiteral(GetObj(te, 'lanes'));
    elem_tid := ResolveTypeExpr(GetObj(te, 'element_type'));
    { Power-of-two probe by successive halving -- the source language's AND
      is boolean-only (no bitwise integer AND), so the classic
      `count AND (count-1) = 0` idiom is not expressible here. }
    pow2 := count;
    WHILE (pow2 > 1) AND ((pow2 MOD 2) = 0) DO pow2 := pow2 DIV 2;
    IF (count < 2) OR (count > 64) OR (pow2 <> 1) THEN
      AbortWith('codegen: vector lane count must be a power of two between 2 and 64');
    IF (elem_tid < TK_INTEGER) OR (elem_tid > TK_REAL32) THEN
      AbortWith('codegen: vector element type must be a scalar');
    { BOOLEAN vectors are <n x i8> in memory (0/1 per lane), not <n x i1>:
      byte-wide storage keeps SIZEOF, alignment and VAR storage uniform
      with every other type. }
    IF elem_tid = TK_BOOLEAN THEN
      arr_ty := LLVMVectorType(i8ty, count)
    ELSE
      arr_ty := LLVMVectorType(LLVMTypeForTk(elem_tid), count);
    tid := RegisterType(TK_VECTOR, elem_tid, 0, count - 1, arr_ty);
  END
  ELSE IF nt = 'RecordType' THEN
  BEGIN
    IF GetBool(te, 'packed') THEN
      AbortWith('codegen: PACKED records are not supported');
    fields_arr := GetObj(te, 'fields');
    variants_arr := GetObj(te, 'variants');
    has_variants := ArrSize(variants_arr) > 0;
    nfd := ArrSize(fields_arr);
    field_index := 0;
    fixed_off := 0;
    elem_llvm_types := AllocPtrArray(MAX_RECORD_FIELDS);
    tid := RegisterType(TK_RECORD, 0, 0, 0, NIL); { patched below }
    { Fixed fields, including a named discriminant, are real struct members. }
    FOR fi := 0 TO nfd - 1 DO
    BEGIN
      field_tuple := ArrItem(fields_arr, fi); items := GetObj(field_tuple, 'items');
      fnames_arr := ArrItem(items, 0); ftype_expr := ArrItem(items, 1);
      field_tid := ResolveTypeExpr(ftype_expr);
      FOR fni := 0 TO ArrSize(fnames_arr) - 1 DO
      BEGIN
        fixed_off := RoundUpBytes(fixed_off, TypeAlignBytes(field_tid));
        fname := CStrToStr255(cJSON_GetStringValue(ArrItem(fnames_arr, fni)));
        nfields := nfields + 1; fields[nfields].rec_tid := tid; fields[nfields].fname := fname;
        fields[nfields].field_tid := field_tid; fields[nfields].field_index := field_index;
        fields[nfields].byte_offset := fixed_off;
        SetPtrArrayElem(elem_llvm_types, field_index, LLVMTypeForTk(field_tid));
        fixed_off := fixed_off + TypeSizeBytes(field_tid); field_index := field_index + 1;
      END;
    END;
    IF has_variants AND GetBool(te, 'has_tag') THEN
    BEGIN
      tag_type_expr := GetObj(te, 'tag_type'); tag_tid := ResolveTypeExpr(tag_type_expr);
      fixed_off := RoundUpBytes(fixed_off, TypeAlignBytes(tag_tid));
      nfields := nfields + 1; fields[nfields].rec_tid := tid; fields[nfields].fname := GetStr(te, 'tag_name');
      fields[nfields].field_tid := tag_tid; fields[nfields].field_index := field_index;
      fields[nfields].byte_offset := fixed_off;
      SetPtrArrayElem(elem_llvm_types, field_index, LLVMTypeForTk(tag_tid));
      fixed_off := fixed_off + TypeSizeBytes(tag_tid); field_index := field_index + 1;
    END;
    { Every arm begins at the same aligned payload offset. }
    payload_align := 1;
    FOR ai := 0 TO ArrSize(variants_arr) - 1 DO
    BEGIN
      arm_node := ArrItem(variants_arr, ai); fields_arr := GetObj(arm_node, 'fields');
      FOR fi := 0 TO ArrSize(fields_arr) - 1 DO
      BEGIN
        field_tuple := ArrItem(fields_arr, fi); items := GetObj(field_tuple, 'items');
        field_tid := ResolveTypeExpr(ArrItem(items, 1));
        IF TypeAlignBytes(field_tid) > payload_align THEN payload_align := TypeAlignBytes(field_tid);
      END;
    END;
    fixed_off := RoundUpBytes(fixed_off, payload_align);
    payload_size := 0;
    FOR ai := 0 TO ArrSize(variants_arr) - 1 DO
    BEGIN
      arm_off := fixed_off; arm_node := ArrItem(variants_arr, ai); fields_arr := GetObj(arm_node, 'fields');
      FOR fi := 0 TO ArrSize(fields_arr) - 1 DO
      BEGIN
        field_tuple := ArrItem(fields_arr, fi); items := GetObj(field_tuple, 'items'); fnames_arr := ArrItem(items, 0);
        field_tid := ResolveTypeExpr(ArrItem(items, 1)); arm_off := RoundUpBytes(arm_off, TypeAlignBytes(field_tid));
        FOR fni := 0 TO ArrSize(fnames_arr) - 1 DO
        BEGIN
          fname := CStrToStr255(cJSON_GetStringValue(ArrItem(fnames_arr, fni)));
          nfields := nfields + 1; fields[nfields].rec_tid := tid; fields[nfields].fname := fname;
          fields[nfields].field_tid := field_tid; fields[nfields].field_index := field_index;
          fields[nfields].byte_offset := arm_off;
          arm_off := arm_off + TypeSizeBytes(field_tid);
        END;
      END;
      IF arm_off - fixed_off > payload_size THEN payload_size := arm_off - fixed_off;
    END;
    IF payload_size > 0 THEN
    BEGIN
      { Use an element with the payload's maximum alignment, not i8 storage. }
      IF payload_align >= 8 THEN payload_ty := i64ty
      ELSE IF payload_align >= 4 THEN payload_ty := i32ty
      ELSE IF payload_align >= 2 THEN payload_ty := i16ty
      ELSE payload_ty := i8ty;
      count := (payload_size + payload_align - 1) DIV payload_align;
      SetPtrArrayElem(elem_llvm_types, field_index, LLVMArrayType(payload_ty, count));
      field_index := field_index + 1;
    END;
    struct_ty := LLVMStructTypeInContext(ctx, elem_llvm_types, field_index, 0);
    types[tid].llvm_ty := struct_ty;
  END
  ELSE IF nt = 'PointerType' THEN
  BEGIN
    flavor := GetStr(te, 'flavor');
    IF (flavor <> 'POINTER') AND (flavor <> 'ADS') THEN
      AbortWith('codegen: only POINTER and device ADS pointers are supported');
    IF (flavor = 'ADS') AND (NOT is_device_compiland) THEN
      AbortWith('codegen: ADS pointers require a DEVICE compiland');
    elem_tid := ResolveTypeExpr(GetObj(te, 'base'));
    { A pointer's flavor and, for ADS, its space are part of its identity for
      assignment compatibility (PTR_SPACE_PLAIN and the PTR_SPACE_* codes are
      what TypesCompatibleForAssign compares), so they are resolved for every
      compiland. The LLVM address space is a separate question: only NVPTX has
      the ABI-defined GLOBAL/SHARED/CONSTANT/LOCAL spaces, and the CPU device
      collapses all of them to address space zero. }
    IF flavor = 'ADS' THEN
    BEGIN
      space_name := GetStr(GetObj(te, 'space'), 'name');
      IF space_name = 'GLOBAL' THEN space_code := PTR_SPACE_GLOBAL
      ELSE IF space_name = 'SHARED' THEN space_code := PTR_SPACE_SHARED
      ELSE IF space_name = 'CONSTANT' THEN space_code := PTR_SPACE_CONSTANT
      ELSE IF space_name = 'LOCAL' THEN space_code := PTR_SPACE_LOCAL
      ELSE IF space_name = 'HOST' THEN space_code := PTR_SPACE_HOST
      ELSE
      BEGIN
        AbortWith2('codegen: unsupported ADS space: ', space_name);
        space_code := PTR_SPACE_HOST;
      END;
    END
    ELSE space_code := PTR_SPACE_PLAIN;
    lo := 0;
    IF is_nvptx_device THEN
    BEGIN
      IF space_code = PTR_SPACE_GLOBAL THEN lo := 1
      ELSE IF space_code = PTR_SPACE_SHARED THEN lo := 3
      ELSE IF space_code = PTR_SPACE_CONSTANT THEN lo := 4
      ELSE IF space_code = PTR_SPACE_LOCAL THEN lo := 5;
    END;
    arr_ty := LLVMPointerType(LLVMTypeForTk(elem_tid), lo);
    tid := RegisterType(TK_POINTER, elem_tid, 0, 0, arr_ty);
    types[tid].ptr_space := space_code;
  END
  ELSE IF nt = 'FileType' THEN
  BEGIN
    elem_tid := ResolveTypeExpr(GetObj(te, 'element_type'));
    IF GetStr(te, 'structure') = 'ASCII' THEN hi := 1 ELSE hi := 0;
    tid := RegisterType(TK_FILE, elem_tid, 0, hi, i8ptrty);
  END
  ELSE IF nt = 'SetType' THEN
  BEGIN
    { Every SET type shares the same physical [4 x i64] 256-bit-bitvector
      representation regardless of declared base range (matching the Python
      reference's set_llvm_type) -- only the base's low/high are kept, and
      only to know the ordinal's legal range, not to size the storage.
      Two base shapes: a SubrangeType (SET OF lo..hi, always an INTEGER
      ordinal here since this dialect only lexes plain-integer subrange
      bounds in this position) or a bare ordinal type name -- CHAR, WORD,
      BOOLEAN, or INTEGER -- parsed by ParseSetBase as either a NamedType
      (e.g. a bare identifier) or a BuiltinType node (a reserved-word type
      name). The manual's own worked example (djvu.txt:7107-7126) is
      `SET OF CHAR`, so this case has to exist, not just SubrangeType. }
    IF NodeType(GetObj(te, 'base')) = 'SubrangeType' THEN
    BEGIN
      lo := ResolveIntLiteral(GetObj(GetObj(te, 'base'), 'low'));
      hi := ResolveIntLiteral(GetObj(GetObj(te, 'base'), 'high'));
      tid := RegisterType(TK_SET, TK_INTEGER, lo, hi, setty);
    END
    ELSE IF (NodeType(GetObj(te, 'base')) = 'NamedType') OR (NodeType(GetObj(te, 'base')) = 'BuiltinType') THEN
    BEGIN
      nm := GetStr(GetObj(te, 'base'), 'name');
      unm := UpperStr(nm);
      IF unm = 'CHAR' THEN tid := RegisterType(TK_SET, TK_CHAR, 0, 255, setty)
      ELSE IF unm = 'BOOLEAN' THEN tid := RegisterType(TK_SET, TK_BOOLEAN, 0, 1, setty)
      ELSE IF (unm = 'INTEGER') OR (unm = 'WORD') THEN tid := RegisterType(TK_SET, TK_INTEGER, 0, 255, setty)
      ELSE
      BEGIN
        AbortWith2('codegen: SET OF <base> requires an ordinal base type (INTEGER subrange, CHAR, WORD, or BOOLEAN), got: ', nm);
        tid := TK_UNKNOWN;
      END;
    END
    ELSE
    BEGIN
      AbortWith('codegen: SET OF <base> is only supported over a lo..hi subrange or an ordinal named type');
      tid := TK_UNKNOWN;
    END;
  END
  ELSE IF nt = 'EnumType' THEN
  BEGIN
    { An enumerated type: i32 storage holding the 0-based ordinal, matching
      the reference's EnumType lowering. Each member identifier is
      registered in const_tbl at its ordinal -- the native counterpart of
      the reference's own constants-table registration (codegen/decls.py's
      self.constants) -- which is what lets a member stand anywhere a
      compile-time integer constant is legal (array bounds, FOR bounds,
      CASE arms). The bounds recorded on the type are the ordinal range.
      Vintage I/O uses that ordinal, while extended I/O uses the retained
      member names. }
    values_arr := GetObj(te, 'values');
    count := ArrSize(values_arr);
    tid := RegisterType(TK_ENUM, 0, 0, RETYPE(INTEGER, count - 1), i32ty);
    types[tid].enum_values := values_arr;
    FOR mi := 0 TO count - 1 DO
    BEGIN
      fname := CStrToStr255(cJSON_GetStringValue(ArrItem(values_arr, mi)));
      IF LookupConst(fname) <> 0 THEN
        AbortWith2('codegen: duplicate const declaration: ', fname);
      IF nconsts >= MAX_CONSTS THEN AbortWith('codegen: too many consts');
      nconsts := nconsts + 1;
      const_tbl[nconsts].name := fname;
      const_tbl[nconsts].is_real := FALSE;
      const_tbl[nconsts].is_char := FALSE;
      const_tbl[nconsts].enum_tid := tid;
      const_tbl[nconsts].integer_tid := 0;
      const_tbl[nconsts].ival := mi;
    END;
  END
  ELSE
  BEGIN
    AbortWith2('codegen: unsupported type expression: ', nt);
    tid := TK_UNKNOWN;
  END;
  ResolveTypeExpr := tid;
END;


BEGIN
END.
