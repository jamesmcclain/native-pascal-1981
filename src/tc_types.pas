{ Type-expression resolution implementation. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_types.inc'*)
IMPLEMENTATION OF tc_types;

FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;

FUNCTION VectorScalarElemTk(tk: INTEGER): BOOLEAN;
{ The element kinds a VECTOR may hold: the integer family, REAL, BOOLEAN,
  CHAR. Pointers, strings, arrays, records, sets, files, enums and other
  vectors are diagnostics. REAL32 keeps its own tag so f32 vector lanes do
  not become indistinguishable from REAL's f64 lanes. The vintage 16-bit
  INTEGER/WORD pair is deliberately included: vectors of the dialect's
  default width are exactly representable. }
BEGIN
  VectorScalarElemTk := (tk = TK_INTEGER) OR (tk = TK_WORD) OR
    (tk = TK_INTEGER8) OR (tk = TK_WORD8) OR (tk = TK_INTEGER32) OR
    (tk = TK_WORD32) OR (tk = TK_INTEGER64) OR (tk = TK_WORD64) OR
    (tk = TK_REAL) OR (tk = TK_REAL32) OR (tk = TK_BOOLEAN) OR (tk = TK_CHAR);
END;

FUNCTION EnumIdOfNode(node: ADRMEM): INTEGER;
{ The id an already resolved EnumType node was given, or 0. Pure. }
VAR
  k: INTEGER32;
  id: INTEGER;
BEGIN
  id := 0;
  k := nenum_nodes;
  WHILE (k >= 1) AND THEN (enum_nodes[k] <> node) DO k := k - 1;
  IF k >= 1 THEN id := enum_node_ids[k];
  EnumIdOfNode := id;
END;

FUNCTION FoldVectorLanes(node: ADRMEM): INTEGER;
{ The lane count is a full constant-expression AST node. The acceptance rule
  both stages implement identically: an integer literal, or an identifier
  naming a previously-declared integer CONST (tc_decl sets has_const_int/
  const_int for those). Computed expressions are deliberately not folded --
  the codegen side's ResolveIntLiteral accepts exactly the same two forms,
  so the two stages can never disagree about what a legal lane count is.
  Returns -1 for anything unresolvable; the caller diagnoses. }
VAR
  nm: Str255;
  si: INTEGER32;
BEGIN
  IF NodeType(node) = 'IntLiteral' THEN
    FoldVectorLanes := RETYPE(INTEGER, GetInt(node, 'value'))
  ELSE IF NodeType(node) = 'Identifier' THEN
  BEGIN
    nm := GetStr(node, 'name');
    si := LookupSymbol(nm);
    IF si <> 0 THEN
    BEGIN
      { has_const_int also covers CHAR and BOOLEAN CONSTs; a lane count
        is an integer. }
      IF symbols[si].has_const_int AND IsInteger(symbols[si].tk) THEN
        FoldVectorLanes := RETYPE(INTEGER, symbols[si].const_int)
      ELSE
        FoldVectorLanes := -1;
    END
    ELSE
      FoldVectorLanes := -1;
  END
  ELSE
    FoldVectorLanes := -1;
END;

{ ============================ constant folding ========================= }

VAR
  fold_overflowed: BOOLEAN; { set by FoldArith; see CheckFoldedOperation }
  fold_overflow_negative: BOOLEAN;

FUNCTION JsonIntegerValue(node: ADRMEM): INTEGER64;
BEGIN
  { Exact, not through GetReal: a JSON number keeps 15 digits. }
  JsonIntegerValue := GetInt64(node, 'value');
END;

FUNCTION IsWord64Literal(node: ADRMEM): BOOLEAN;
{ An IntLiteral of 2^63 or more: its value field is the WORD64 bit
  pattern, negative as an INTEGER64. }
BEGIN
  IsWord64Literal := FALSE;
  IF node <> NIL THEN
    IF NodeType(node) = 'IntLiteral' THEN
      IsWord64Literal := GetBool(node, 'word64');
END;

FUNCTION MinInteger64Value: INTEGER64;
VAR
  n, low: INTEGER64;
BEGIN
  { -2^63 from vintage-sized literals, as MaxInteger32Value in tc_expr. }
  n := 16384;
  n := n * 4;                    { 2^16 }
  low := n * n * 32768;
  low := -low;                   { -(2^47); Pascal's - binds below * }
  MinInteger64Value := low * n;
END;

FUNCTION IsNegatedMinInt64(node: ADRMEM): BOOLEAN;
{ -9223372036854775808: unary minus of the WORD64 literal 2^63, whose bit
  pattern is already the INTEGER64 minimum. }
VAR
  operand: ADRMEM;
BEGIN
  IsNegatedMinInt64 := FALSE;
  IF GetStr(node, 'op') = 'MINUS' THEN
  BEGIN
    operand := GetObj(node, 'operand');
    IF IsWord64Literal(operand) THEN
      IsNegatedMinInt64 := JsonIntegerValue(operand) = MinInteger64Value;
  END;
END;

FUNCTION FoldArith(op: Str255; left, right: INTEGER64;
  VAR folded: INTEGER64): BOOLEAN;
{ The exact constant left + - * right, or FALSE when it leaves INTEGER64.
  The folder runs inside a MATHCK-checked compiler, so a constant from the
  program must not trap it: the operation wraps and the overflow is tested
  explicitly. A failure sets fold_overflowed and records the sign of the
  exact value in fold_overflow_negative for CheckFoldedOperation. }
VAR
  r, neg_right: INTEGER64;
  fits: BOOLEAN;
BEGIN
  (*$MATHCK-*)
  IF op = 'PLUS' THEN r := left + right
  ELSE IF op = 'MINUS' THEN r := left - right
  ELSE r := left * right;
  neg_right := 0 - right;
  (*$MATHCK+*)
  IF op = 'PLUS' THEN
    fits := ((left >= 0) <> (right >= 0)) OR ((r >= 0) = (left >= 0))
  ELSE IF op = 'MINUS' THEN
    fits := ((left >= 0) = (right >= 0)) OR ((r >= 0) = (left >= 0))
  ELSE IF (left = 0) OR (right = 0) THEN
    fits := TRUE
  ELSE IF left = -1 THEN
    fits := neg_right <> right { only the minimum negates to itself }
  ELSE
    fits := r DIV left = right;
  IF NOT fits THEN
  BEGIN
    fold_overflowed := TRUE;
    IF op = 'MUL' THEN fold_overflow_negative := (left < 0) <> (right < 0)
    ELSE fold_overflow_negative := left < 0;
  END;
  folded := r;
  FoldArith := fits;
END;

FUNCTION LowByte(x: INTEGER64): INTEGER64;
{ The low eight bits of x, 0..255, as CHR and BYWORD convert an ordinal.
  MOD is dividend-signed; never negate MIN64 to get its low byte. }
VAR
  b: INTEGER64;
BEGIN
  b := x MOD 256;
  IF b < 0 THEN b := b + 256;
  LowByte := b;
END;

FUNCTION FoldConstInt(node: ADRMEM; VAR folded_value: INTEGER64): BOOLEAN;
{ The integer constant folder. Codegen's FoldConstIntIn (cg_types.pas)
  applies the same rule when it decides what is an integer constant, and
  states it with its one deliberate difference: a name folds when its
  innermost visible declaration is a CONST with has_const_int (never an
  enumeration member), and an intrinsic call when no user declaration of
  its name is visible or, in a constant expression, always
  (UserDeclarationShadows). }
VAR
  nt, op, name, ch: Str255;
  left, right: INTEGER64;
  si: INTEGER32;
  args: ADRMEM;
BEGIN
  nt := NodeType(node);
  FoldConstInt := FALSE;
  IF nt = 'IntLiteral' THEN
  BEGIN
    { A WORD64 literal of 2^63 or more has no INTEGER64 value to fold; it
      stays a typed WORD64 operand (CheckExpr). }
    folded_value := JsonIntegerValue(node);
    FoldConstInt := NOT IsWord64Literal(node);
  END
  ELSE IF nt = 'BoolLiteral' THEN
  BEGIN
    IF GetBool(node, 'value') THEN folded_value := 1 ELSE folded_value := 0;
    FoldConstInt := TRUE;
  END
  ELSE IF nt = 'CharLiteral' THEN
  BEGIN
    ch := GetStr(node, 'value');
    folded_value := ORD(ch[1]);
    FoldConstInt := TRUE;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    op := GetStr(node, 'op');
    IF IsNegatedMinInt64(node) THEN
    BEGIN
      folded_value := JsonIntegerValue(GetObj(node, 'operand'));
      FoldConstInt := TRUE;
    END
    ELSE IF ((op = 'PLUS') OR (op = 'MINUS')) AND FoldConstInt(GetObj(node, 'operand'), folded_value) THEN
    BEGIN
      IF op = 'MINUS' THEN
        FoldConstInt := FoldArith('MINUS', 0, folded_value, folded_value)
      ELSE
        FoldConstInt := TRUE;
    END;
  END
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    op := GetStr(node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') OR
        (op = 'DIV') OR (op = 'MOD')) AND
       FoldConstInt(GetObj(node, 'left'), left) AND
       FoldConstInt(GetObj(node, 'right'), right) THEN
    BEGIN
      IF (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') THEN
        FoldConstInt := FoldArith(op, left, right, folded_value)
      ELSE IF right = -1 THEN
      BEGIN
        { x DIV -1 is -x, which overflows only for the minimum; x MOD -1
          is 0. }
        IF op = 'DIV' THEN FoldConstInt := FoldArith('MINUS', 0, left, folded_value)
        ELSE
        BEGIN
          folded_value := 0;
          FoldConstInt := TRUE;
        END;
      END
      ELSE IF right <> 0 THEN
      BEGIN
        { Truncate toward zero; MOD has the dividend's sign, like runtime. }
        IF op = 'DIV' THEN folded_value := left DIV right
        ELSE folded_value := left MOD right;
        FoldConstInt := TRUE;
      END;
      { A zero divisor does not fold. The BinOp check in CheckExpr reports
        it once; this folder also answers "is it constant?" for callers. }
    END;
  END
  ELSE IF (nt = 'Identifier') OR (nt = 'Designator') THEN
  BEGIN
    IF (nt = 'Identifier') OR (cJSON_GetArraySize(GetObj(node, 'selectors')) = 0) THEN
    BEGIN
      name := GetStr(node, 'name');
      si := LookupSymbol(name);
      IF si <> 0 THEN
        IF symbols[si].has_const_int THEN
        BEGIN
          folded_value := symbols[si].const_int;
          FoldConstInt := TRUE;
        END;
    END;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    name := UpperStr(GetStr(node, 'name'));
    args := GetObj(node, 'args');
    IF (name = 'BYWORD') AND NOT UserDeclarationShadows(name) AND
       (cJSON_GetArraySize(args) = 2) AND
       FoldConstInt(cJSON_GetArrayItem(args, 0), left) AND
       FoldConstInt(cJSON_GetArrayItem(args, 1), right) THEN
    BEGIN
      { The backend checks the original enabled domain; this folder keeps
        the converted WORD ordinal, as with CHR's low-byte normalization. }
      folded_value := LowByte(left) * 256 + LowByte(right);
      FoldConstInt := TRUE;
    END
    ELSE IF (name = 'WRD') AND (const_expr_level > 0) AND
       (cJSON_GetArraySize(args) = 1) AND
       FoldConstInt(cJSON_GetArrayItem(args, 0), folded_value) THEN
    BEGIN
      { WRD is a constant function only in a constant expression (a CONST
        value or a bound), where it folds to its WORD bit pattern: WRD(-2)
        is 65534 (IBM 11-8). Elsewhere it stays a conversion, as codegen's
        FoldConstIntIn keeps it outside a constant expression. }
      folded_value := folded_value MOD 65536;
      IF folded_value < 0 THEN folded_value := folded_value + 65536;
      FoldConstInt := TRUE;
    END
    ELSE IF NOT UserDeclarationShadows(name) AND
       ((name = 'ORD') OR (name = 'CHR') OR (name = 'SUCC') OR (name = 'PRED') OR
        (name = 'ABS') OR (name = 'SQR')) AND
       (cJSON_GetArraySize(args) = 1) AND
       FoldConstInt(cJSON_GetArrayItem(args, 0), folded_value) THEN
    BEGIN
      IF name = 'CHR' THEN
      BEGIN
        { CHR's value is its low eight bits, not its original argument.
          The backend independently enforces enabled CHR's original domain. }
        folded_value := LowByte(folded_value);
        FoldConstInt := TRUE;
      END
      ELSE IF name = 'SUCC' THEN FoldConstInt := FoldArith('PLUS', folded_value, 1, folded_value)
      ELSE IF name = 'PRED' THEN FoldConstInt := FoldArith('MINUS', folded_value, 1, folded_value)
      ELSE IF name = 'SQR' THEN FoldConstInt := FoldArith('MUL', folded_value, folded_value, folded_value)
      ELSE IF (name = 'ABS') AND (folded_value < 0) THEN
        FoldConstInt := FoldArith('MINUS', 0, folded_value, folded_value)
      ELSE FoldConstInt := TRUE;
    END;
  END;
END;

PROCEDURE CheckConstByteDomain(node: ADRMEM);
{ A folded constant expression is never lowered to a call, so the runtime
  RANGECK guard of a BYWORD or CHR inside it never runs. Report, at the
  call's name token, an operand outside 0..255 when the call's own RANGECK
  snapshot is on. Codegen declines to fold such a call, so a fold this
  check does not cover becomes a guarded runtime call. Only the shapes a
  constant expression can take are walked; a CONST name was checked at
  its own declaration. }
VAR
  nm: Str255;
  args: ADRMEM;
  i: INTEGER32;
  hi, lo: INTEGER64;
  saved_line, saved_col: INTEGER32;
  saved_loc: ADRMEM;
  bad: BOOLEAN;
BEGIN
  IF NodeType(node) = 'UnaryOp' THEN
    CheckConstByteDomain(GetObj(node, 'operand'))
  ELSE IF NodeType(node) = 'BinOp' THEN
  BEGIN
    CheckConstByteDomain(GetObj(node, 'left'));
    CheckConstByteDomain(GetObj(node, 'right'));
  END
  ELSE IF NodeType(node) = 'FuncCall' THEN
  BEGIN
    nm := UpperStr(GetStr(node, 'name'));
    IF UserDeclarationShadows(nm) THEN RETURN;
    args := GetObj(node, 'args');
    FOR i := 0 TO cJSON_GetArraySize(args) - 1 DO
      CheckConstByteDomain(cJSON_GetArrayItem(args, i));
    IF NOT GetBool(node, 'rangeck') THEN RETURN;
    bad := FALSE;
    IF (nm = 'BYWORD') AND (cJSON_GetArraySize(args) = 2) THEN
    BEGIN
      IF FoldConstInt(cJSON_GetArrayItem(args, 0), hi) AND
         FoldConstInt(cJSON_GetArrayItem(args, 1), lo) THEN
        bad := (hi < 0) OR (hi > 255) OR (lo < 0) OR (lo > 255);
    END
    ELSE IF (nm = 'CHR') AND (cJSON_GetArraySize(args) = 1) THEN
      IF FoldConstInt(cJSON_GetArrayItem(args, 0), lo) THEN
        bad := (lo < 0) OR (lo > 255);
    IF bad THEN
    BEGIN
      TcEnterLocation(node, saved_line, saved_col, saved_loc);
      IF nm = 'BYWORD' THEN AddError('RANGECK constant BYWORD argument outside 0..255')
      ELSE AddError('RANGECK constant CHR argument outside 0..255');
      TcLeaveLocation(saved_line, saved_col, saved_loc);
    END;
  END;
END;

{ ========================== type-expr resolution ======================= }

FUNCTION IsSuperTypeExpr(node: ADRMEM): BOOLEAN;
VAR
  ti: INTEGER32;
BEGIN
  IsSuperTypeExpr := FALSE;
  IF NodeType(node) = 'ArrayType' THEN
    IsSuperTypeExpr := GetBool(node, 'super')
  ELSE IF NodeType(node) = 'NamedType' THEN
  BEGIN
    ti := LookupType(GetStr(node, 'name'));
    IF ti <> 0 THEN IsSuperTypeExpr := types[ti].is_super;
  END;
END;

FUNCTION SemanticOrdinalBase(tk, aux: INTEGER): INTEGER;
{ The host of an ordinal type. Subranges keep their host TK; enum types
  additionally carry the declaration id in aux. Never infer a host from a
  numeric ordinal, or treat missing enum identity as generic INTEGER. }
BEGIN
  SemanticOrdinalBase := SB_UNKNOWN;
  IF tk = TK_ENUM THEN
  BEGIN
    IF aux > 0 THEN SemanticOrdinalBase := SB_ENUM_OFFSET + aux;
  END
  ELSE IF IsOrdinal(tk) THEN SemanticOrdinalBase := tk;
END;

FUNCTION ConstCallBoundKind(node: ADRMEM): INTEGER;
{ The ordinal kind of a subrange or array index bound written as one of
  the constant calls ParseConstant admits, as codegen's BoundHostTid
  classifies it: CHAR for CHR, the argument's kind for SUCC and PRED, and
  INTEGER for ORD, WRD and BYWORD. Any other node is TK_UNKNOWN; the
  callers keep their own rules for literals and names. }
VAR
  nt, name: Str255;
  args, arg: ADRMEM;
  si: INTEGER32;
BEGIN
  ConstCallBoundKind := TK_UNKNOWN;
  IF NodeType(node) <> 'FuncCall' THEN RETURN;
  name := UpperStr(GetStr(node, 'name'));
  args := GetObj(node, 'args');
  IF name = 'CHR' THEN ConstCallBoundKind := TK_CHAR
  ELSE IF (name = 'ORD') OR (name = 'WRD') OR (name = 'BYWORD') THEN
    ConstCallBoundKind := TK_INTEGER
  ELSE IF ((name = 'SUCC') OR (name = 'PRED')) AND (cJSON_GetArraySize(args) = 1) THEN
  BEGIN
    arg := cJSON_GetArrayItem(args, 0);
    nt := NodeType(arg);
    IF nt = 'IntLiteral' THEN ConstCallBoundKind := TK_INTEGER
    ELSE IF nt = 'CharLiteral' THEN ConstCallBoundKind := TK_CHAR
    ELSE IF nt = 'BoolLiteral' THEN ConstCallBoundKind := TK_BOOLEAN
    ELSE IF nt = 'Identifier' THEN
    BEGIN
      si := LookupSymbol(GetStr(arg, 'name'));
      IF si <> 0 THEN ConstCallBoundKind := symbols[si].tk;
    END
    ELSE ConstCallBoundKind := ConstCallBoundKind(arg);
  END;
END;

FUNCTION BoundValueKind(bound_value: INTEGER64): INTEGER;
{ The narrowest of INTEGER, WORD and INTEGER32 that holds a non-negative
  bound: the one rule (NEW-5) for an integer index range, a STRING(n)
  capacity's LOWER/UPPER and an integer subrange's host. Codegen's
  cg_types BoundValueTid is the same rule. INTEGER32 arises only in the
  extended dialect, where bounds may exceed 65535. }
BEGIN
  IF bound_value > 65535 THEN BoundValueKind := TK_INTEGER32
  ELSE IF bound_value > 32767 THEN BoundValueKind := TK_WORD
  ELSE BoundValueKind := TK_INTEGER;
END;

FUNCTION WidenBoundHostKind(kind: INTEGER; high_node: ADRMEM): INTEGER;
{ The host kind of an integer range `low..high' whose low bound alone
  gives kind: an INTEGER or WORD host widens to hold the folded upper
  bound (BoundValueKind), however it is spelled, so 0..40000 is a WORD
  range and (extended only) 0..70000 an INTEGER32 one, as the IBM manual
  types `0..50000' (5-7). Any other kind, or a bound that does not fold,
  is kept. Codegen's cg_types WidenBoundHostTid is the same rule. }
VAR
  bound_value: INTEGER64;
BEGIN
  WidenBoundHostKind := kind;
  IF high_node = NIL THEN RETURN;
  IF (kind <> TK_INTEGER) AND (kind <> TK_WORD) THEN RETURN;
  IF NOT FoldConstInt(high_node, bound_value) THEN RETURN;
  IF BoundValueKind(bound_value) <> TK_INTEGER THEN
    WidenBoundHostKind := BoundValueKind(bound_value);
END;

FUNCTION SubrangeHostKind(range_node: ADRMEM): INTEGER;
{ The host kind of a subrange or array index range `low..high': the low
  bound's kind (a literal's, a named constant's or enumeration member's,
  a constant call's; a signed CONST name is an integer), widened to hold
  the upper bound when it is an integer (WidenBoundHostKind). TK_UNKNOWN when
  the low bound names nothing. No diagnostics: the declaration's own
  check (CheckSubrangeEndpoints) reports bad endpoints. }
VAR
  low_node: ADRMEM;
  nt: Str255;
  si: INTEGER32;
  kind: INTEGER;
BEGIN
  low_node := GetObj(range_node, 'low');
  nt := NodeType(low_node);
  kind := TK_INTEGER;
  IF nt = 'CharLiteral' THEN kind := TK_CHAR
  ELSE IF nt = 'BoolLiteral' THEN kind := TK_BOOLEAN
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    si := LookupSymbol(GetStr(low_node, 'name'));
    IF si <> 0 THEN kind := symbols[si].tk ELSE kind := TK_UNKNOWN;
  END
  ELSE IF nt = 'FuncCall' THEN
    kind := ConstCallBoundKind(low_node)
  ELSE IF (nt = 'IntLiteral') AND (GetInt(low_node, 'value') > 32767) THEN
    kind := TK_WORD;
  SubrangeHostKind := WidenBoundHostKind(kind, GetObjOrNil(range_node, 'high'));
END;

FUNCTION SemanticBaseOfOrdinalType(node: ADRMEM): INTEGER;
{ Resolve the semantic host without re-running ResolveTypeExpr (which can
  emit diagnostics and allocate enum ids). This also handles the SubrangeType
  syntax used as a SET base, whose low endpoint determines its host. }
VAR
  nt, name: Str255;
  ti: INTEGER32;
  low_node: ADRMEM;
  host: INTEGER;
BEGIN
  SemanticBaseOfOrdinalType := SB_UNKNOWN;
  nt := NodeType(node);
  IF (nt = 'NamedType') OR (nt = 'BuiltinType') THEN
  BEGIN
    name := UpperStr(GetStr(node, 'name'));
    ti := LookupType(name);
    IF ti <> 0 THEN
      SemanticBaseOfOrdinalType := types[ti].scalar_sem_base
    ELSE IF name = 'INTEGER' THEN SemanticBaseOfOrdinalType := TK_INTEGER
    ELSE IF name = 'WORD' THEN SemanticBaseOfOrdinalType := TK_WORD
    ELSE IF name = 'BOOLEAN' THEN SemanticBaseOfOrdinalType := TK_BOOLEAN
    ELSE IF name = 'CHAR' THEN SemanticBaseOfOrdinalType := TK_CHAR;
  END
  ELSE IF (nt = 'SubrangeType') OR (nt = 'IndexRange') THEN
  BEGIN
    { An array's explicit index range (IndexRange) has the same `low`
      field; a SUPER ARRAY's missing high bound does not matter here. }
    low_node := GetObj(node, 'low');
    nt := NodeType(low_node);
    IF nt = 'IntLiteral' THEN SemanticBaseOfOrdinalType := TK_INTEGER
    ELSE IF nt = 'CharLiteral' THEN SemanticBaseOfOrdinalType := TK_CHAR
    ELSE IF nt = 'BoolLiteral' THEN SemanticBaseOfOrdinalType := TK_BOOLEAN
    ELSE IF nt = 'Identifier' THEN
    BEGIN
      ti := LookupSymbol(GetStr(low_node, 'name'));
      IF ti <> 0 THEN
        SemanticBaseOfOrdinalType := symbols[ti].scalar_sem_base;
    END
    ELSE IF nt = 'FuncCall' THEN
      SemanticBaseOfOrdinalType := SemanticOrdinalBase(ConstCallBoundKind(low_node), 0)
    ELSE IF nt = 'UnaryOp' THEN
    BEGIN
      { A signed bound (-N): its operand is a numeric CONST name (only a
        word64 literal keeps its sign as an operator). }
      low_node := GetObj(low_node, 'operand');
      IF NodeType(low_node) = 'Identifier' THEN
      BEGIN
        ti := LookupSymbol(GetStr(low_node, 'name'));
        IF ti <> 0 THEN
          SemanticBaseOfOrdinalType := symbols[ti].scalar_sem_base;
      END
      ELSE SemanticBaseOfOrdinalType := TK_INTEGER;
    END;
    { An integer range widens to hold its bounds, as its host does
      (SubrangeHostKind): 0..40000 has the WORD identity. }
    host := SubrangeHostKind(node);
    IF (host = TK_WORD) OR (host = TK_INTEGER32) THEN
      SemanticBaseOfOrdinalType := host;
  END
  ELSE IF nt = 'EnumType' THEN
    { An anonymous enumeration: the id its node was resolved to. }
    SemanticBaseOfOrdinalType := SemanticOrdinalBase(TK_ENUM, EnumIdOfNode(node));
END;

FUNCTION SemanticSetBaseType(node: ADRMEM): INTEGER;
{ Set semantic identity is deliberately separate from the existing aux TK
  used by LOWER/UPPER. Named aliases inherit the declaration's identity. }
VAR
  ti: INTEGER32;
BEGIN
  SemanticSetBaseType := SB_UNKNOWN;
  IF NodeType(node) = 'SetType' THEN
    SemanticSetBaseType := SemanticBaseOfOrdinalType(GetObj(node, 'base'))
  ELSE IF NodeType(node) = 'NamedType' THEN
  BEGIN
    ti := LookupType(GetStr(node, 'name'));
    IF ti <> 0 THEN
      IF types[ti].tk = TK_SET THEN SemanticSetBaseType := types[ti].set_sem_base;
  END;
END;

FUNCTION SemanticChildTypeNode(node: ADRMEM; bound: INTEGER32): ADRMEM;
{ Follow exactly one array index, pointer/file dereference. A NamedType
  is expanded only on demand, so forward pointer targets can be resolved
  after their TYPE section is complete; do not recursively expand records
  here (self-referential records are legal). Names resolve among
  types[1..bound] (LookupTypeBefore), the types the declaration saw. }
VAR
  nt: Str255;
  ti: INTEGER32;
BEGIN
  SemanticChildTypeNode := NIL;
  IF node = NIL THEN RETURN;
  nt := NodeType(node);
  IF (nt = 'NamedType') OR (nt = 'BuiltinType') THEN
  BEGIN
    ti := LookupTypeBefore(GetStr(node, 'name'), bound);
    IF ti <> 0 THEN SemanticChildTypeNode := SemanticChildTypeNode(types[ti].type_node, bound);
  END
  ELSE IF nt = 'ArrayType' THEN
    SemanticChildTypeNode := GetObj(node, 'element_type')
  ELSE IF nt = 'PointerType' THEN
    SemanticChildTypeNode := GetObj(node, 'base')
  ELSE IF nt = 'FileType' THEN
    SemanticChildTypeNode := GetObj(node, 'element_type');
END;

FUNCTION RecordIdOfNode(node: ADRMEM): INTEGER;
{ The record id an already resolved RecordType node was given, or 0. Each
  field entry keeps its declared type node, a child of exactly one record
  node, so the field whose type node is this record's first field (or tag)
  type node names the record. Pure: no id is reserved, no field added. }
VAR
  probe, arms, arm_fields: ADRMEM;
  k: INTEGER32;
  rid: INTEGER;
BEGIN
  probe := NIL;
  IF cJSON_GetArraySize(GetObj(node, 'fields')) > 0 THEN
    probe := cJSON_GetArrayItem(GetObj(cJSON_GetArrayItem(GetObj(node, 'fields'), 0), 'items'), 1)
  ELSE IF GetBool(node, 'has_tag') THEN
    probe := GetObj(node, 'tag_type')
  ELSE
  BEGIN
    arms := GetObj(node, 'variants');
    FOR k := cJSON_GetArraySize(arms) - 1 DOWNTO 0 DO
    BEGIN
      arm_fields := GetObj(cJSON_GetArrayItem(arms, k), 'fields');
      IF cJSON_GetArraySize(arm_fields) > 0 THEN
        probe := cJSON_GetArrayItem(GetObj(cJSON_GetArrayItem(arm_fields, 0), 'items'), 1);
    END;
  END;
  rid := 0;
  IF probe <> NIL THEN
  BEGIN
    k := nfields;
    WHILE (k >= 1) AND THEN (fields[k].type_node <> probe) DO k := k - 1;
    IF k >= 1 THEN rid := fields[k].record_id;
  END;
  RecordIdOfNode := rid;
END;

FUNCTION TypeNodeMetadata(node: ADRMEM; bound: INTEGER32;
                          VAR tk, aux, aux2, aux3, idx_tk: INTEGER): BOOLEAN;
{ The flat (tk, aux, aux2, aux3, idx_tk) metadata of an already declared
  type node, composed the way ResolveTypeExpr composes it but without its
  effects: no diagnostics, no new record or enumeration ids, no fields.
  Anonymous enumerations (by the id their node was given), subranges,
  vectors and sets are read too. FALSE when the node cannot be read that
  way (an unresolved enumeration or an unknown record). A name means the TYPE among
  types[1..bound], as for SemanticChildTypeNode. The flat model
  keeps only three levels below a pointer, array or file, so selectors use
  this to recover the metadata a deeper level lost (CheckDesignator). }
VAR
  nt: Str255;
  ok: BOOLEAN;
  saved_errors, ti: INTEGER32;
  inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx, lanes: INTEGER;
BEGIN
  tk := TK_UNKNOWN;
  aux := 0;
  aux2 := 0;
  aux3 := 0;
  idx_tk := 0;
  ok := FALSE;
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    IF nt = 'NamedType' THEN
    BEGIN
      ti := 0;
      IF GetObjOrNil(node, 'param') = NIL THEN
        ti := LookupTypeBefore(GetStr(node, 'name'), bound);
      IF ti <> 0 THEN
      BEGIN
        tk := types[ti].tk;
        aux := types[ti].aux;
        aux2 := types[ti].aux2;
        aux3 := types[ti].aux3;
        idx_tk := types[ti].idx_tk;
        ok := TRUE;
      END
      ELSE IF (GetObjOrNil(node, 'param') <> NIL) OR
              (LookupType(GetStr(node, 'name')) = 0) THEN
      BEGIN
        { A predeclared name (INTEGER, TEXT, STRING(n), ...) that no user
          TYPE hides: ResolveTypeExpr only spells it out. Its diagnostics
          were reported at the declaration, so a repeat is dropped. }
        saved_errors := nerrors;
        ResolveTypeExpr(node, tk, aux, aux2, aux3, idx_tk);
        nerrors := saved_errors;
        ok := tk <> TK_UNKNOWN;
      END;
    END
    ELSE IF nt = 'RecordType' THEN
    BEGIN
      aux := RecordIdOfNode(node);
      IF aux <> 0 THEN
      BEGIN
        tk := TK_RECORD;
        ok := TRUE;
      END;
    END
    ELSE IF (nt = 'PointerType') OR (nt = 'ArrayType') OR (nt = 'FileType') THEN
    BEGIN
      IF nt = 'PointerType' THEN
        ok := TypeNodeMetadata(GetObj(node, 'base'), bound, inner_tk, inner_aux,
                               inner_aux2, inner_aux3, inner_idx)
      ELSE
        ok := TypeNodeMetadata(GetObj(node, 'element_type'), bound, inner_tk, inner_aux,
                               inner_aux2, inner_aux3, inner_idx);
      IF ok THEN
      BEGIN
        aux := inner_tk;
        IF nt = 'FileType' THEN
        BEGIN
          tk := TK_FILE;
          IF GetStr(node, 'structure') = 'ASCII' THEN aux2 := 1;
        END
        ELSE
        BEGIN
          IF (inner_tk = TK_STRING) AND (inner_aux2 = 1) THEN aux2 := 1
          ELSE aux2 := inner_aux;
          aux3 := inner_aux2;
          IF nt = 'PointerType' THEN
          BEGIN
            tk := TK_POINTER;
            idx_tk := inner_idx;
          END
          ELSE
          BEGIN
            tk := TK_ARRAY;
            idx_tk := ElementIndexKind(node, bound);
            IF idx_tk = TK_UNKNOWN THEN idx_tk := TK_INTEGER;
          END;
        END;
      END;
    END
    ELSE IF nt = 'EnumType' THEN
    BEGIN
      { An anonymous enumeration: the id its node was resolved to. }
      aux := EnumIdOfNode(node);
      IF aux <> 0 THEN
      BEGIN
        tk := TK_ENUM;
        ok := TRUE;
      END;
    END
    ELSE IF nt = 'SubrangeType' THEN
    BEGIN
      { As ResolveTypeExprBody: the host kind is SubrangeHostKind's, and
        aux -1 marks the subrange declaration shape. }
      tk := SubrangeHostKind(node);
      IF IsOrdinal(tk) THEN
      BEGIN
        aux := -1;
        ok := TRUE;
      END
      ELSE tk := TK_UNKNOWN;
    END
    ELSE IF nt = 'VectorType' THEN
    BEGIN
      { VECTOR [n] OF scalar: the element kind in aux, the lanes in aux2. }
      lanes := FoldVectorLanes(GetObj(node, 'lanes'));
      IF TypeNodeMetadata(GetObj(node, 'element_type'), bound, inner_tk, inner_aux,
                          inner_aux2, inner_aux3, inner_idx) THEN
        IF VectorScalarElemTk(inner_tk) AND (lanes >= 2) AND (lanes <= 64) THEN
        BEGIN
          tk := TK_VECTOR;
          aux := inner_tk;
          aux2 := lanes;
          ok := TRUE;
        END;
    END
    ELSE IF nt = 'SetType' THEN
    BEGIN
      IF TypeNodeMetadata(GetObj(node, 'base'), bound, inner_tk, inner_aux,
                          inner_aux2, inner_aux3, inner_idx) THEN
        IF IsOrdinal(inner_tk) THEN
        BEGIN
          tk := TK_SET;
          aux := inner_tk;
          ok := TRUE;
        END;
    END;
  END;
  TypeNodeMetadata := ok;
END;

PROCEDURE RefineFromTypeNode(node: ADRMEM; bound: INTEGER32;
                             VAR tk, aux, aux2, aux3, idx_tk: INTEGER);
{ Fill the metadata slots a selector chain lost (left 0) from the type
  node it reached, when the node agrees on the kind. Slots the chain still
  carries are kept, so this only ever adds what the flat model dropped:
  a record id, an element's slots, an enumeration id, a VECTOR's element
  kind and lanes, a subrange's aux -1 marker. }
VAR
  rtk, raux, raux2, raux3, ridx: INTEGER;
BEGIN
  IF tk <> TK_UNKNOWN THEN
    IF TypeNodeMetadata(node, bound, rtk, raux, raux2, raux3, ridx) THEN
      IF rtk = tk THEN
      BEGIN
        IF aux = 0 THEN aux := raux;
        IF aux2 = 0 THEN aux2 := raux2;
        IF aux3 = 0 THEN aux3 := raux3;
        IF idx_tk = TK_UNKNOWN THEN idx_tk := ridx;
      END;
END;

FUNCTION SubrangeEndpointClass(node: ADRMEM): INTEGER;
{ The ordinal kind of a subrange endpoint that is a literal, a named
  constant or enumeration member, or a constant call: TK_INTEGER for any
  integer, else TK_CHAR, TK_BOOLEAN or TK_ENUM. Anything else is
  TK_UNKNOWN, so it is not compared. }
VAR
  nt: Str255;
  si: INTEGER32;
  kind: INTEGER;
BEGIN
  SubrangeEndpointClass := TK_UNKNOWN;
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN SubrangeEndpointClass := TK_INTEGER
  ELSE IF nt = 'CharLiteral' THEN SubrangeEndpointClass := TK_CHAR
  ELSE IF nt = 'BoolLiteral' THEN SubrangeEndpointClass := TK_BOOLEAN
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    si := LookupSymbol(GetStr(node, 'name'));
    IF si <> 0 THEN
      IF IsInteger(symbols[si].tk) THEN SubrangeEndpointClass := TK_INTEGER
      ELSE IF (symbols[si].tk = TK_CHAR) OR (symbols[si].tk = TK_BOOLEAN) OR
              (symbols[si].tk = TK_ENUM) THEN
        SubrangeEndpointClass := symbols[si].tk;
  END
  ELSE IF nt = 'FuncCall' THEN
  BEGIN
    kind := ConstCallBoundKind(node);
    IF IsInteger(kind) THEN SubrangeEndpointClass := TK_INTEGER
    ELSE IF (kind = TK_CHAR) OR (kind = TK_BOOLEAN) OR (kind = TK_ENUM) THEN
      SubrangeEndpointClass := kind;
  END;
END;

PROCEDURE CheckSubrangeEndpoints(range_node: ADRMEM);
{ Both ends of a subrange must be the same ordinal type: FALSE..2 or
  'a'..150 used to be accepted, with the type (and storage) taken from the
  low end alone, so the high bound was silently narrowed. A bound is a
  constant consumer like a CONST value: an enabled out-of-domain CHR or
  BYWORD in it (CHR(300)) is a located error here, since codegen would
  never fold it into a bound. }
VAR
  high_node: ADRMEM;
  lo_class, hi_class: INTEGER;
BEGIN
  CheckConstByteDomain(GetObj(range_node, 'low'));
  high_node := GetObjOrNil(range_node, 'high');
  IF high_node = NIL THEN RETURN;
  CheckConstByteDomain(high_node);
  lo_class := SubrangeEndpointClass(GetObj(range_node, 'low'));
  hi_class := SubrangeEndpointClass(high_node);
  IF (lo_class <> TK_UNKNOWN) AND (hi_class <> TK_UNKNOWN) AND (lo_class <> hi_class) THEN
    AddError('Subrange bounds must be of the same ordinal type');
END;

FUNCTION ArrayNameEqual(a, b: Str255): BOOLEAN;
VAR
  i: INTEGER;
BEGIN
  a := UpperStr(a);
  b := UpperStr(b);
  ArrayNameEqual := FALSE;
  IF ORD(a[0]) <> ORD(b[0]) THEN RETURN;
  FOR i := 1 TO ORD(a[0]) DO
    IF a[i] <> b[i] THEN RETURN;
  ArrayNameEqual := TRUE;
END;

FUNCTION ArrayIndexBound(node: ADRMEM; enum_id: INTEGER; VAR ordinal_value: INTEGER64): BOOLEAN;
{ Evaluate an ordinal endpoint in its declaration's domain, not as an
  unrelated integer CONST. Enum member ordinals come from the defining enum. }
VAR
  nt, nm, member_name: Str255;
  si, ti, i, n: INTEGER32;
  vals: ADRMEM;
BEGIN
  ArrayIndexBound := TRUE;
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN ordinal_value := GetInt(node, 'value')
  ELSE IF nt = 'BoolLiteral' THEN
  BEGIN
    ordinal_value := 0;
    IF GetBool(node, 'value') THEN ordinal_value := 1;
  END
  ELSE IF nt = 'CharLiteral' THEN
  BEGIN
    nm := GetStr(node, 'value');
    ordinal_value := ORD(nm[1]);
  END
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    nm := GetStr(node, 'name');
    si := LookupSymbol(nm);
    IF si = 0 THEN ArrayIndexBound := FALSE
    ELSE IF symbols[si].has_const_int THEN ordinal_value := symbols[si].const_int
    ELSE IF (enum_id > 0) AND (symbols[si].tk = TK_ENUM) AND
            (symbols[si].aux = enum_id) THEN
    BEGIN
      ArrayIndexBound := FALSE;
      FOR ti := 1 TO ntypes DO
        IF (types[ti].tk = TK_ENUM) AND (types[ti].aux = enum_id) AND
           (NodeType(types[ti].type_node) = 'EnumType') THEN
        BEGIN
          vals := GetObj(types[ti].type_node, 'values');
          n := cJSON_GetArraySize(vals);
          FOR i := 0 TO n - 1 DO
          BEGIN
            member_name := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(vals, i)));
            IF ArrayNameEqual(member_name, nm) THEN
            BEGIN
              ordinal_value := i;
              ArrayIndexBound := TRUE;
            END;
          END;
        END;
    END
    ELSE ArrayIndexBound := FALSE;
  END
  ELSE
    { A constant call folds to its converted ordinal (CHR(250) is 250), as
      codegen's ResolveIntLiteral folds the same bound; so does a signed
      CONST name (-N). }
    ArrayIndexBound := FoldConstInt(node, ordinal_value);
END;

FUNCTION NamedArrayIndexBounds(node: ADRMEM; tk, enum_id: INTEGER;
                               VAR low, high: INTEGER64): BOOLEAN;
{ Follow aliases to the declaration that owns the domain. For a subrange
  retain its endpoints; for an enum use the declaration's member count. }
VAR
  nt, name: Str255;
  ti, n, depth: INTEGER32;
  vals: ADRMEM;
  ok_low, ok_high: BOOLEAN;
BEGIN
  NamedArrayIndexBounds := FALSE;
  FOR depth := 1 TO MAX_TYPES DO
  BEGIN
    nt := NodeType(node);
    IF nt = 'NamedType' THEN
    BEGIN
      name := GetStr(node, 'name');
      ti := LookupType(name);
      IF ti <> 0 THEN node := types[ti].type_node
      ELSE BEGIN
        node := NIL;
        nt := 'BuiltinType';
      END;
    END;
    IF nt = 'SubrangeType' THEN
    BEGIN
      IF tk = TK_ENUM THEN
        IF NodeType(GetObj(node, 'low')) = 'Identifier' THEN
        BEGIN
          ti := LookupSymbol(GetStr(GetObj(node, 'low'), 'name'));
          IF ti <> 0 THEN enum_id := symbols[ti].aux;
        END;
      ok_low := ArrayIndexBound(GetObj(node, 'low'), enum_id, low);
      ok_high := ArrayIndexBound(GetObj(node, 'high'), enum_id, high);
      NamedArrayIndexBounds := ok_low AND ok_high;
      RETURN;
    END
    ELSE IF nt = 'EnumType' THEN
    BEGIN
      vals := GetObj(node, 'values');
      n := cJSON_GetArraySize(vals);
      low := 0;
      high := n - 1;
      NamedArrayIndexBounds := n > 0;
      RETURN;
    END
    ELSE IF nt = 'BuiltinType' THEN node := NIL;
    IF node = NIL THEN
    BEGIN
      IF tk = TK_BOOLEAN THEN BEGIN low := 0; high := 1; END
      ELSE IF tk = TK_CHAR THEN BEGIN low := 0; high := 255; END
      ELSE IF tk = TK_INTEGER THEN BEGIN low := -32768; high := 32767; END
      ELSE IF tk = TK_WORD THEN BEGIN low := 0; high := 65535; END
      ELSE IF tk = TK_INTEGER8 THEN BEGIN low := -128; high := 127; END
      ELSE IF tk = TK_WORD8 THEN BEGIN low := 0; high := 255; END
      ELSE IF tk = TK_INTEGER32 THEN BEGIN low := -2147483647 - 1; high := 2147483647; END
      ELSE IF tk = TK_WORD32 THEN BEGIN low := 0; high := 4294967295; END
      { INTEGER64 and WORD64 fall through to RETURN: their domains are not
        representable in this function's INTEGER32 bounds, so they are
        rejected at typecheck like any other unresolvable domain, before
        codegen would have to reject the size. }
      ELSE RETURN;
      NamedArrayIndexBounds := TRUE;
      RETURN;
    END;
  END;
END;

FUNCTION PendingFwdType(base_node: ADRMEM): INTEGER32;
{ The fwd_types index of the not-yet-declared TYPE that a pointer's base
  names, or 0. Standard Pascal lets a pointer type name a type declared
  later in the same TYPE section, and that later declaration wins over an
  outer type of the same name, so this is consulted before LookupType. The
  declaration being checked counts as pending: `N = RECORD next: ^N END'. }
VAR
  k, found: INTEGER32;
  uname: Str255;
BEGIN
  found := 0;
  IF nfwd_types > 0 THEN
    IF NodeType(base_node) = 'NamedType' THEN
      IF GetObjOrNil(base_node, 'param') = NIL THEN
      BEGIN
        uname := UpperStr(GetStr(base_node, 'name'));
        FOR k := nfwd_types DOWNTO fwd_cur DO
          IF UpperStr(fwd_types[k].name) = uname THEN found := k;
      END;
  PendingFwdType := found;
END;

PROCEDURE ResolveFwdType(k: INTEGER32; VAR tk, aux, aux2, aux3, idx_tk: INTEGER);
{ What a pointer's forward base resolves to. A record target gets its
  record id now, which its own declaration adopts later (FwdRecordId), so
  a record and a pointer to it can refer to each other. Any other target is
  resolved once, here, and cached for its own declaration to reuse. }
BEGIN
  aux2 := 0;
  aux3 := 0;
  idx_tk := 0;
  IF NodeType(fwd_types[k].node) = 'RecordType' THEN
  BEGIN
    IF fwd_types[k].rid = 0 THEN
    BEGIN
      fwd_types[k].rid := next_record_id;
      next_record_id := next_record_id + 1;
    END;
    tk := TK_RECORD;
    aux := fwd_types[k].rid;
  END
  ELSE IF fwd_types[k].state = 1 THEN
  BEGIN
    AddError2('Pointer type cycle through type: ', fwd_types[k].name);
    tk := TK_UNKNOWN;
    aux := 0;
  END
  ELSE
  BEGIN
    IF fwd_types[k].state = 0 THEN
    BEGIN
      fwd_types[k].state := 1;
      ResolveTypeExpr(fwd_types[k].node, fwd_types[k].tk, fwd_types[k].aux,
                      fwd_types[k].aux2, fwd_types[k].aux3, fwd_types[k].idx_tk);
      fwd_types[k].state := 2;
    END;
    tk := fwd_types[k].tk;
    aux := fwd_types[k].aux;
    aux2 := fwd_types[k].aux2;
    aux3 := fwd_types[k].aux3;
    idx_tk := fwd_types[k].idx_tk;
  END;
END;

FUNCTION RecordIdFor(node: ADRMEM): INTEGER;
{ The record id for this RecordType: the one a forward pointer already
  reserved for it, or a new one. A new id for a TYPE section's own record is
  also recorded there before any field is resolved, so a field pointing
  back at the record being declared (`next: ^N') shares it. }
VAR
  k, found: INTEGER32;
  rid: INTEGER;
BEGIN
  found := 0;
  FOR k := 1 TO nfwd_types DO
    IF fwd_types[k].node = node THEN found := k;
  rid := 0;
  IF found <> 0 THEN rid := fwd_types[found].rid;
  IF rid = 0 THEN
  BEGIN
    rid := next_record_id;
    next_record_id := next_record_id + 1;
    IF found <> 0 THEN fwd_types[found].rid := rid;
  END;
  RecordIdFor := rid;
END;

FUNCTION FwdCachedType(node: ADRMEM; VAR tk, aux, aux2, aux3, idx_tk: INTEGER): BOOLEAN;
{ TRUE, with the resolution, when a forward pointer already resolved this
  non-record type_expr: its declaration reuses that instead of resolving it
  a second time (and reporting any error in it twice). }
VAR
  k: INTEGER32;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  FOR k := 1 TO nfwd_types DO
    IF fwd_types[k].node = node THEN
      IF fwd_types[k].state = 2 THEN
      BEGIN
        found := TRUE;
        tk := fwd_types[k].tk;
        aux := fwd_types[k].aux;
        aux2 := fwd_types[k].aux2;
        aux3 := fwd_types[k].aux3;
        idx_tk := fwd_types[k].idx_tk;
      END;
  FwdCachedType := found;
END;

FUNCTION SubrangeIndexKind(index_node: ADRMEM): INTEGER;
{ The coarse scalar kind of an explicit `low..high` array index range:
  SubrangeHostKind, the rule a subrange's host follows, so an integer
  index takes the narrowest of INTEGER, WORD and INTEGER32 that holds its
  bounds (NEW-5): `0..70000' (extended only) is an INTEGER32 index, so
  UPPER is 70000, not its low 16 bits. A low bound naming nothing is
  INTEGER. No diagnostics: ResolveTypeExpr checks the endpoints itself.
  Codegen's cg_types ResolveTypeExpr applies the same rule to index_tid. }
VAR
  kind: INTEGER;
BEGIN
  kind := SubrangeHostKind(index_node);
  IF kind = TK_UNKNOWN THEN kind := TK_INTEGER;
  SubrangeIndexKind := kind;
END;

FUNCTION ElementIndexKind(node: ADRMEM; bound: INTEGER32): INTEGER;
{ The index kind of an array type node (an element reached through an
  INDEX selector), or TK_UNKNOWN when node is not an array or its index
  cannot be read without resolving the type again. Pure: the declaration
  was already resolved and diagnosed. }
VAR
  nt: Str255;
  index_node: ADRMEM;
  ti: INTEGER32;
BEGIN
  ElementIndexKind := TK_UNKNOWN;
  IF node = NIL THEN RETURN;
  nt := NodeType(node);
  IF (nt = 'NamedType') OR (nt = 'BuiltinType') THEN
  BEGIN
    ti := LookupTypeBefore(GetStr(node, 'name'), bound);
    IF ti <> 0 THEN
      IF types[ti].tk = TK_ARRAY THEN ElementIndexKind := types[ti].idx_tk;
  END
  ELSE IF nt = 'ArrayType' THEN
  BEGIN
    index_node := GetObj(node, 'index_range');
    IF (NodeType(index_node) = 'NamedType') OR
       (NodeType(index_node) = 'BuiltinType') THEN
    BEGIN
      ti := LookupTypeBefore(GetStr(index_node, 'name'), bound);
      IF ti <> 0 THEN
        IF IsOrdinal(types[ti].tk) THEN ElementIndexKind := types[ti].tk;
    END
    ELSE IF NodeType(index_node) = 'IndexRange' THEN
      ElementIndexKind := SubrangeIndexKind(index_node);
  END;
END;

FUNCTION ArrayIndexSemBase(node: ADRMEM; bound: INTEGER32): INTEGER;
{ The semantic base (SemanticOrdinalBase identity) of an array type node's
  index, so two enumerations can be told apart where idx_tk only says
  TK_ENUM. SB_UNKNOWN when node is not an array or the index base cannot
  be read without resolving the type again. }
VAR
  nt: Str255;
  ti: INTEGER32;
BEGIN
  ArrayIndexSemBase := SB_UNKNOWN;
  IF node = NIL THEN RETURN;
  nt := NodeType(node);
  IF (nt = 'NamedType') OR (nt = 'BuiltinType') THEN
  BEGIN
    ti := LookupTypeBefore(GetStr(node, 'name'), bound);
    IF ti <> 0 THEN
      IF types[ti].tk = TK_ARRAY THEN
        ArrayIndexSemBase := ArrayIndexSemBase(types[ti].type_node, bound);
  END
  ELSE IF nt = 'ArrayType' THEN
    ArrayIndexSemBase := SemanticBaseOfOrdinalType(GetObj(node, 'index_range'));
END;

FUNCTION Int64Text(n: INTEGER64): Str255;
{ Decimal text of n, sign included, for a diagnostic. }
VAR
  digits, t: Str255;
  d: INTEGER64;
  i: INTEGER;
  neg, first: BOOLEAN;
BEGIN
  neg := n < 0;
  digits := '';
  first := TRUE;
  WHILE first OR (n <> 0) DO
  BEGIN
    first := FALSE;
    d := n MOD 10;
    IF d < 0 THEN d := -d;
    digits[0] := CHR(ORD(digits[0]) + 1);
    digits[ORD(digits[0])] := CHR(RETYPE(INTEGER, ORD('0') + d));
    n := n DIV 10;
  END;
  t := '';
  IF neg THEN
  BEGIN
    t[0] := CHR(1);
    t[1] := '-';
  END;
  FOR i := ORD(digits[0]) DOWNTO 1 DO
  BEGIN
    t[0] := CHR(ORD(t[0]) + 1);
    t[ORD(t[0])] := digits[i];
  END;
  Int64Text := t;
END;

PROCEDURE CheckStringCapacity(node: ADRMEM; uname: Str255);
{ The capacity n of STRING(n) or LSTRING(n) is an integer constant: a
  literal, a CONST name, or a signed name or constant call, which the
  parser keeps as an expression (`param'). A STRING needs at least one
  character and an LSTRING at least its length byte; neither goes past
  the limit of an array bound (vintage 65535, extended the INTEGER32
  maximum). STRING(-3) used to become a 4 GiB array and STRING(-N) a bare
  STRING. }
VAR
  param: ADRMEM;
  pname, msg: Str255;
  si: INTEGER32;
  cap, low, high: INTEGER64;
  ok: BOOLEAN;
  ptk: INTEGER;
BEGIN
  param := GetObjOrNil(node, 'param');
  IF param = NIL THEN RETURN;
  ok := FALSE;
  pname := GetStr(node, 'param');
  IF pname <> '' THEN
  BEGIN
    si := LookupSymbol(pname);
    IF si <> 0 THEN
      IF (symbols[si].kind = 'CONST') AND IsInteger(symbols[si].tk) AND
         symbols[si].has_const_int THEN
      BEGIN
        cap := symbols[si].const_int;
        ok := TRUE;
      END;
    IF si = 0 THEN
    BEGIN
      AddError2('Undefined identifier: ', pname);
      RETURN;
    END;
  END
  ELSE IF NodeType(param) <> '' THEN
  BEGIN
    { ParseConstant's other shapes: a signed name, a constant call, or a
      non-integer literal. }
    IF NodeType(param) = 'UnaryOp' THEN
      ptk := SubrangeEndpointClass(GetObj(param, 'operand'))
    ELSE
      ptk := SubrangeEndpointClass(param);
    IF ptk = TK_INTEGER THEN ok := FoldConstInt(param, cap);
  END
  ELSE
  BEGIN
    cap := GetInt64(node, 'param');
    ok := TRUE;
  END;
  msg := uname;
  IF NOT ok THEN
  BEGIN
    CONCAT(msg, ' capacity must be an integer constant');
    AddError(msg);
    RETURN;
  END;
  IF uname = 'STRING' THEN low := 1 ELSE low := 0;
  IF active_features.wide_integers THEN high := 2147483647 ELSE high := 65535;
  IF (cap < low) OR (cap > high) THEN
  BEGIN
    CONCAT(msg, ' capacity ');
    CONCAT(msg, Int64Text(cap));
    CONCAT(msg, ' is outside ');
    CONCAT(msg, Int64Text(low));
    CONCAT(msg, '..');
    CONCAT(msg, Int64Text(high));
    AddError(msg);
  END;
END;

FUNCTION StringBoundKind(node: ADRMEM; bound: INTEGER32): INTEGER;
{ The type of LOWER and UPPER of a STRING(n) or LSTRING(n) type node:
  the narrowest of INTEGER, WORD and INTEGER32 that holds its capacity n,
  as for an array index range (SubrangeIndexKind), so UPPER of an
  LSTRING(40000) is the WORD 40000, not -25536 (NEW-24). Codegen's
  UpperExpr applies the same rule to the capacity it has. TK_UNKNOWN when
  node is not a sized string type or n does not fold; the declaration was
  already diagnosed (CheckStringCapacity). Names resolve among
  types[1..bound]; a named type's own node among the types before it. }
VAR
  nt, pname: Str255;
  ti, si: INTEGER32;
  param: ADRMEM;
  cap: INTEGER64;
  ok: BOOLEAN;
BEGIN
  StringBoundKind := TK_UNKNOWN;
  IF node = NIL THEN RETURN;
  nt := NodeType(node);
  IF (nt <> 'NamedType') AND (nt <> 'BuiltinType') THEN RETURN;
  ti := LookupTypeBefore(GetStr(node, 'name'), bound);
  IF ti <> 0 THEN
  BEGIN
    StringBoundKind := StringBoundKind(types[ti].type_node, ti - 1);
    RETURN;
  END;
  IF (UpperStr(GetStr(node, 'name')) <> 'STRING') AND
     (UpperStr(GetStr(node, 'name')) <> 'LSTRING') THEN RETURN;
  param := GetObjOrNil(node, 'param');
  IF param = NIL THEN RETURN;
  ok := FALSE;
  pname := GetStr(node, 'param');
  IF pname <> '' THEN
  BEGIN
    si := LookupSymbol(pname);
    IF si <> 0 THEN
      IF (symbols[si].kind = 'CONST') AND symbols[si].has_const_int THEN
      BEGIN
        cap := symbols[si].const_int;
        ok := TRUE;
      END;
  END
  ELSE IF NodeType(param) <> '' THEN
    ok := FoldConstInt(param, cap)
  ELSE
  BEGIN
    cap := GetInt64(node, 'param');
    ok := TRUE;
  END;
  IF NOT ok THEN RETURN;
  StringBoundKind := BoundValueKind(cap);
END;

PROCEDURE CheckIntegerSubrangeBounds(node: ADRMEM; host: INTEGER);
{ The folded bounds of an integer subrange, checked here rather than in
  codegen. They stay within an array bound's limits (-32768 up to 65535
  in vintage, which has no INTEGER32, and up to the INTEGER32 maximum in
  extended), so a vintage `0..70000' is an error, as the IBM manual says
  of `0..80000' (5-7). The lower bound must not exceed the upper. A
  negative lower bound in a WORD subrange is reversed too: the IBM manual
  reads `-1..50000' as `65535..50000', and the extended dialect follows
  it rather than widening to INTEGER32 (only an upper bound above 65535
  does that). }
VAR
  low, high, limit: INTEGER64;
BEGIN
  IF NOT IsInteger(host) THEN RETURN;
  IF NOT FoldConstInt(GetObj(node, 'low'), low) THEN RETURN;
  IF NOT FoldConstInt(GetObj(node, 'high'), high) THEN RETURN;
  IF active_features.wide_integers THEN limit := 2147483647 ELSE limit := 65535;
  IF low < -32768 THEN
    AddError('Subrange lower bound is below -32768')
  ELSE IF high > limit THEN
  BEGIN
    IF active_features.wide_integers THEN
      AddError('Subrange upper bound is above 2147483647')
    ELSE
      AddError('Subrange upper bound is above 65535');
  END
  ELSE IF (host = TK_WORD) AND (low < 0) THEN
    AddError('Subrange lower bound is negative in a WORD subrange')
  ELSE IF low > high THEN
    AddError('Subrange lower bound exceeds upper bound');
END;

PROCEDURE CheckSetBaseRange(base_node: ADRMEM; base_tk, base_aux: INTEGER);
{ "The ORD value of the base type can range from 0 to 255, allowing SET
  OF CHAR but not SET OF 1942..1984" (IBM manual 6-24). The base's
  ordinal bounds are resolved as an array index type's are, so a literal,
  CONST, signed CONST or named subrange bound, an enumeration and a
  predeclared type (INTEGER, WORD) all get the same diagnostic. SET OF
  -3..3 used to fail only at run time, and SET OF -N..N with an unrelated
  type error. }
VAR
  low, high: INTEGER64;
  msg: Str255;
BEGIN
  IF NamedArrayIndexBounds(base_node, base_tk, base_aux, low, high) THEN
  BEGIN
    IF (low < 0) OR (high > 255) THEN
    BEGIN
      msg := 'SET base type ordinals ';
      CONCAT(msg, Int64Text(low));
      CONCAT(msg, '..');
      CONCAT(msg, Int64Text(high));
      CONCAT(msg, ' are outside 0..255');
      AddError(msg);
    END;
  END
  ELSE IF IsInteger(base_tk) AND (IntegerBits(base_tk) = 64) THEN
    AddError('SET base type ordinals are outside 0..255');
END;

PROCEDURE ResolveTypeExprBody(node: ADRMEM; VAR tk, aux, aux2, aux3, idx_tk: INTEGER);
VAR
  nt, name, uname: Str255;
  base_node, elem_node, index_node, bound_node, fields_arr, tup, items, names_arr, ftype_node: ADRMEM;
  variants_arr, arm_node, tag_type_node: ADRMEM;
  inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx: INTEGER;
  lanes_v, pow2, index_kind, index_aux, index_aux2, index_aux3, index_idx: INTEGER;
  index_low, index_high: INTEGER64;
  ti, fwd_k: INTEGER32;
  rid: INTEGER;
  n, fi, nn, ni, bound_si: INTEGER32;
  nm: Str255;
BEGIN
  tk := TK_UNKNOWN;
  aux := 0;
  aux2 := 0;
  aux3 := 0;
  idx_tk := 0;
  nt := NodeType(node);
  IF nt = 'NamedType' THEN
  BEGIN
    name := GetStr(node, 'name');
    uname := UpperStr(name);
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
    ti := 0;
    IF GetObjOrNil(node, 'param') = NIL THEN ti := LookupType(name);
    IF ti <> 0 THEN
    BEGIN
      tk := types[ti].tk;
      aux := types[ti].aux;
      aux2 := types[ti].aux2;
      aux3 := types[ti].aux3;
      idx_tk := types[ti].idx_tk;
    END
    ELSE IF uname = 'INTEGER' THEN tk := TK_INTEGER
    ELSE IF uname = 'WORD' THEN tk := TK_WORD
    ELSE IF uname = 'REAL' THEN tk := TK_REAL
    ELSE IF uname = 'BOOLEAN' THEN tk := TK_BOOLEAN
    ELSE IF uname = 'CHAR' THEN tk := TK_CHAR
    ELSE IF uname = 'STRING' THEN
    BEGIN
      tk := TK_STRING;
      CheckStringCapacity(node, uname);
    END
    { LSTRING shares TK_STRING with the fixed STRING -- this v1 type-kind
      model does not track a string's capacity or flavor -- but the two are
      not interchangeable for .LEN or a COPYLST destination: both require
      an LSTRING's leading length byte. aux2 = 1 tells them apart. }
    ELSE IF uname = 'LSTRING' THEN
    BEGIN
      tk := TK_STRING;
      aux2 := 1;
      CheckStringCapacity(node, uname);
    END
    { Wide integer names retain exact width and signedness. INTEGER16 and
      WORD16 are extension spellings for the vintage 16-bit kinds. }
    ELSE IF (uname = 'INTEGER8') OR (uname = 'INTEGER16') OR (uname = 'INTEGER32') OR (uname = 'INTEGER64') THEN
    BEGIN
      IF active_features.wide_integers OR is_device_compiland THEN
      BEGIN
        IF uname = 'INTEGER8' THEN tk := TK_INTEGER8
        ELSE IF uname = 'INTEGER32' THEN tk := TK_INTEGER32
        ELSE IF uname = 'INTEGER64' THEN tk := TK_INTEGER64
        ELSE tk := TK_INTEGER;
      END
      ELSE BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END;
    END
    ELSE IF (uname = 'WORD8') OR (uname = 'WORD16') OR (uname = 'WORD32') OR (uname = 'WORD64') THEN
    BEGIN
      IF active_features.wide_integers OR is_device_compiland THEN
      BEGIN
        IF uname = 'WORD8' THEN tk := TK_WORD8
        ELSE IF uname = 'WORD32' THEN tk := TK_WORD32
        ELSE IF uname = 'WORD64' THEN tk := TK_WORD64
        ELSE tk := TK_WORD;
      END
      ELSE BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END;
    END
    ELSE IF (uname = 'REAL32') OR (uname = 'REAL64') THEN
    BEGIN
      IF active_features.wide_reals OR is_device_compiland THEN
      BEGIN
        IF uname = 'REAL32' THEN tk := TK_REAL32
        ELSE tk := TK_REAL; { REAL64 is a synonym for REAL. }
      END
      ELSE BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END;
    END
    { ADRMEM/ADSMEM are vintage address types. The CPTR spelling is part of
      the extended C-ABI aliases. All three use the same coarse pointer tag. }
    ELSE IF (uname = 'ADRMEM') OR (uname = 'ADSMEM') THEN
    BEGIN
      tk := TK_POINTER;
      aux := TK_CHAR;
    END
    ELSE IF (uname = 'CPTR') OR (uname = 'CCHAR') OR (uname = 'CSHORT') OR
            (uname = 'CINT') OR (uname = 'CLONG') OR (uname = 'CSIZE_T') OR
            (uname = 'CDOUBLE') THEN
    BEGIN
      IF NOT FeaturesAreExtended(active_features) THEN
      BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END
      ELSE IF uname = 'CPTR' THEN
      BEGIN
        tk := TK_POINTER;
        aux := TK_CHAR;
      END
      ELSE IF uname = 'CCHAR' THEN tk := TK_CHAR
      ELSE IF uname = 'CSHORT' THEN tk := TK_INTEGER
      ELSE IF uname = 'CINT' THEN tk := TK_INTEGER32
      ELSE IF uname = 'CLONG' THEN tk := TK_INTEGER64
      ELSE IF uname = 'CSIZE_T' THEN tk := TK_WORD64
      ELSE tk := TK_REAL;
    END
    ELSE IF uname = 'TEXT' THEN
    BEGIN
      tk := TK_FILE;
      aux := TK_CHAR;
      aux2 := 1; { ASCII/TEXT structure }
    END
    ELSE BEGIN
      ti := LookupType(name);
      IF ti = 0 THEN
      BEGIN
        AddError2('Unknown type name: ', name);
        tk := TK_UNKNOWN;
      END
      ELSE BEGIN
        tk := types[ti].tk;
        aux := types[ti].aux;
        aux2 := types[ti].aux2;
        aux3 := types[ti].aux3;
        idx_tk := types[ti].idx_tk;
      END;
    END;
  END
  ELSE IF nt = 'PointerType' THEN
  BEGIN
    base_node := GetObj(node, 'base');
    fwd_k := PendingFwdType(base_node);
    IF fwd_k <> 0 THEN
      ResolveFwdType(fwd_k, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx)
    ELSE
      ResolveTypeExpr(base_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
    tk := TK_POINTER;
    aux := inner_tk;
    IF (inner_tk = TK_STRING) AND (inner_aux2 = 1) THEN aux2 := 1
    ELSE aux2 := inner_aux;
    aux3 := inner_aux2;
    idx_tk := inner_idx;
  END
  ELSE IF nt = 'FileType' THEN
  BEGIN
    elem_node := GetObj(node, 'element_type');
    ResolveTypeExpr(elem_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
    tk := TK_FILE;
    aux := inner_tk;
    IF GetStr(node, 'structure') = 'ASCII' THEN aux2 := 1 ELSE aux2 := 0;
  END
  ELSE IF nt = 'ArrayType' THEN
  BEGIN
    elem_node := GetObj(node, 'element_type');
    ResolveTypeExpr(elem_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
    tk := TK_ARRAY;
    aux := inner_tk;
    { An LSTRING element has no aux of its own; keep its .LEN marker alive
      by folding it into the array's aux2 (see the string aux2 flag above). }
    IF (inner_tk = TK_STRING) AND (inner_aux2 = 1) THEN aux2 := 1
    ELSE aux2 := inner_aux;
    aux3 := inner_aux2;
    idx_tk := TK_INTEGER;
    index_node := GetObj(node, 'index_range');
    IF (NodeType(index_node) = 'NamedType') OR
       (NodeType(index_node) = 'BuiltinType') THEN
    BEGIN
      { Resolve through TYPE declarations, never through a value symbol.
        Keep the enum declaration id while tracing the bounds through
        aliases; idx_tk itself stores only the coarse scalar kind, as for
        explicit index ranges. A NamedType has no `low` field. }
      IF (NodeType(index_node) = 'NamedType') AND
         (LookupType(GetStr(index_node, 'name')) = 0) AND
         (LookupSymbol(GetStr(index_node, 'name')) <> 0) THEN
        AddError2('Array index requires a type name, not a value: ', GetStr(index_node, 'name'))
      ELSE
      BEGIN
        ResolveTypeExpr(index_node, index_kind, index_aux, index_aux2,
                        index_aux3, index_idx);
        IF (index_kind <> TK_UNKNOWN) AND NOT IsOrdinal(index_kind) THEN
          AddError('Array index type must be ordinal')
        ELSE IF IsOrdinal(index_kind) THEN
        BEGIN
          idx_tk := index_kind;
          IF NOT NamedArrayIndexBounds(index_node, index_kind, index_aux,
                                       index_low, index_high) THEN
            AddError('Array index type has unresolved or unrepresentable ordinal bounds')
          ELSE IF index_low > index_high THEN
            AddError('Array index type has reversed ordinal bounds');
        END;
      END;
      RETURN;
    END;
    CheckSubrangeEndpoints(index_node);
    idx_tk := SubrangeIndexKind(index_node);
  END
  ELSE IF nt = 'VectorType' THEN
  BEGIN
    { VECTOR [n] OF scalar: tk is TK_VECTOR, the element kind rides in aux,
      the lane count in aux2 (the same aux2 slot an LSTRING borrows for its
      .LEN marker), idx_tk unused. Validation happens here, not at the use
      sites, exactly as for ArrayType bounds. }
    { VECTOR is an extended-dialect construct, gated the same way as the wide
      integer/real and C-ABI type names above. A DEVICE compiland is admitted
      here because the typechecker does not receive --device-triple and cannot
      distinguish NVPTX from a serial CPU device; codegen rejects VECTOR for
      NVPTX when is_nvptx_device is TRUE. }
    IF NOT (FeaturesAreExtended(active_features) OR is_device_compiland) THEN
    BEGIN
      AddError('VECTOR types require the extended dialect');
      tk := TK_UNKNOWN;
      RETURN;
    END;
    elem_node := GetObj(node, 'element_type');
    ResolveTypeExpr(elem_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
    bound_node := GetObj(node, 'lanes');
    lanes_v := FoldVectorLanes(bound_node);
    { Power-of-two probe by successive halving: the source language's AND is
      boolean-only (no bitwise integer AND), so the classic
      `n AND (n-1) = 0` idiom is not expressible in this compiler's own
      source. }
    pow2 := lanes_v;
    WHILE (pow2 > 1) AND ((pow2 MOD 2) = 0) DO pow2 := pow2 DIV 2;
    IF NOT VectorScalarElemTk(inner_tk) THEN
    BEGIN
      AddError('Vector element type must be a scalar');
      tk := TK_UNKNOWN;
    END
    ELSE IF (NodeType(bound_node) <> 'IntLiteral') AND (lanes_v < 0) THEN
    BEGIN
      { FoldVectorLanes takes exactly an integer literal or an identifier
        naming an integer CONST -- the same two forms codegen's
        ResolveIntLiteral accepts -- and returns -1 for anything else (a
        computed expression like `VECTOR [2+2]`, or a name that is not an
        integer CONST). Report that on its own; folding it into the range
        message below would misdescribe it as out of range. A genuinely
        negative literal (`VECTOR [-4]`) is an IntLiteral, so it skips this
        arm and lands in the power-of-two check, which is the right message
        for it. }
      AddError('Vector lane count must be an integer literal or a CONST integer identifier');
      tk := TK_UNKNOWN;
    END
    ELSE IF (lanes_v < 2) OR (lanes_v > 64) OR (pow2 <> 1) THEN
    BEGIN
      AddError('Vector lane count must be a power of two between 2 and 64');
      tk := TK_UNKNOWN;
    END
    ELSE
    BEGIN
      tk := TK_VECTOR;
      aux := inner_tk;
      aux2 := lanes_v;
      idx_tk := 0;
    END;
  END
  ELSE IF nt = 'RecordType' THEN
  BEGIN
    rid := RecordIdFor(node);
    fields_arr := GetObj(node, 'fields');
    n := cJSON_GetArraySize(fields_arr);
    FOR fi := 0 TO n - 1 DO
    BEGIN
      tup := cJSON_GetArrayItem(fields_arr, fi);
      items := GetObj(tup, 'items');
      names_arr := cJSON_GetArrayItem(items, 0);
      ftype_node := cJSON_GetArrayItem(items, 1);
      ResolveTypeExpr(ftype_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
      nn := cJSON_GetArraySize(names_arr);
      FOR ni := 0 TO nn - 1 DO
      BEGIN
        nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, ni)));
        AddUniqueRecordField(rid, nm, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
        fields[nfields].is_super := IsSuperTypeExpr(ftype_node);
        fields[nfields].type_node := ftype_node;
        IF inner_tk = TK_SET THEN
          fields[nfields].set_sem_base := SemanticSetBaseType(ftype_node);
        IF IsOrdinal(inner_tk) THEN
          fields[nfields].scalar_sem_base := SemanticBaseOfOrdinalType(ftype_node);
      END;
    END;
    variants_arr := GetObj(node, 'variants');
    IF cJSON_GetArraySize(variants_arr) > 0 THEN
    BEGIN
      tag_type_node := GetObj(node, 'tag_type');
      ResolveTypeExpr(tag_type_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
      IF NOT IsOrdinal(inner_tk) THEN
        AddError('Variant record tag type must be ordinal');
      IF GetBool(node, 'has_tag') THEN
      BEGIN
        nm := GetStr(node, 'tag_name');
        AddUniqueRecordField(rid, nm, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
        fields[nfields].type_node := tag_type_node;
        IF IsOrdinal(inner_tk) THEN
          fields[nfields].scalar_sem_base := SemanticBaseOfOrdinalType(tag_type_node);
      END;
      FOR fi := 0 TO cJSON_GetArraySize(variants_arr) - 1 DO
      BEGIN
        arm_node := cJSON_GetArrayItem(variants_arr, fi);
        fields_arr := GetObj(arm_node, 'fields');
        FOR ni := 0 TO cJSON_GetArraySize(fields_arr) - 1 DO
        BEGIN
          tup := cJSON_GetArrayItem(fields_arr, ni);
          items := GetObj(tup, 'items');
          names_arr := cJSON_GetArrayItem(items, 0);
          ftype_node := cJSON_GetArrayItem(items, 1);
          ResolveTypeExpr(ftype_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
          nn := cJSON_GetArraySize(names_arr);
          FOR n := 0 TO nn - 1 DO
          BEGIN
            nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, n)));
            AddUniqueRecordField(rid, nm, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
            fields[nfields].is_super := IsSuperTypeExpr(ftype_node);
            fields[nfields].type_node := ftype_node;
            IF inner_tk = TK_SET THEN
              fields[nfields].set_sem_base := SemanticSetBaseType(ftype_node);
            IF IsOrdinal(inner_tk) THEN
              fields[nfields].scalar_sem_base := SemanticBaseOfOrdinalType(ftype_node);
          END;
        END;
      END;
    END;
    tk := TK_RECORD;
    aux := rid;
  END
  ELSE IF (nt = 'SubrangeType') OR (nt = 'BuiltinType') THEN
  BEGIN
    { A subrange type (a VAR, TYPE, field or parameter type, or a SetType's
      `base') or a BuiltinType SET base, a reserved-word ordinal type name.
      An ARRAY index range is read by its own caller (SubrangeIndexKind).
      A SubrangeType's host is SubrangeHostKind's: the low bound's kind
      (CHAR for CHR(250), a named constant's kind), and an integer host
      widens to the narrowest of INTEGER, WORD and INTEGER32 that holds
      both bounds (NEW-32), as codegen's subrange types do: `0..40000' is
      a WORD subrange, so `b := 40000' is accepted. }
    IF nt = 'SubrangeType' THEN
    BEGIN
      CheckSubrangeEndpoints(node);
      tk := SubrangeHostKind(node);
      CheckIntegerSubrangeBounds(node, tk);
      { A declared subrange retains its base scalar kind but marks its
        declaration shape for type-only LOWER/UPPER classification. }
      aux := -1;
    END
    ELSE BEGIN
      name := GetStr(node, 'name');
      uname := UpperStr(name);
      { Same shadowing rule as the NamedType branch above. }
      ti := 0;
      IF GetObjOrNil(node, 'param') = NIL THEN ti := LookupType(name);
      IF ti <> 0 THEN
      BEGIN
        { Copy the whole entry, not just the kind -- the payload fields carry
          an element/base kind (aux), a width or capacity (aux2) and an index
          kind (idx_tk), and dropping them silently loses e.g. an LSTRING
          alias's capacity. Same four assignments as the NamedType branch
          above; that they agree is the point. }
        tk := types[ti].tk;
        aux := types[ti].aux;
        aux2 := types[ti].aux2;
        aux3 := types[ti].aux3;
        idx_tk := types[ti].idx_tk;
      END
      ELSE IF uname = 'CHAR' THEN tk := TK_CHAR
      ELSE IF uname = 'BOOLEAN' THEN tk := TK_BOOLEAN
      ELSE IF uname = 'WORD' THEN tk := TK_WORD
      ELSE IF uname = 'INTEGER' THEN tk := TK_INTEGER
      ELSE BEGIN
        AddError('SET OF <base> requires an ordinal base type');
        tk := TK_UNKNOWN;
      END;
    END;
  END
  ELSE IF nt = 'EnumType' THEN
  BEGIN
    { A node gets its id, and its members, once. The members are constants
      of the enumeration in declaration order, declared here so that an
      anonymous enumeration (a field, variable or element type written
      inline) has them as well as a TYPE declaration does: codegen declares
      the members of every EnumType it lowers. }
    tk := TK_ENUM;
    aux := EnumIdOfNode(node);
    IF aux = 0 THEN
    BEGIN
      next_enum_id := next_enum_id + 1;
      aux := next_enum_id;
      IF nenum_nodes < MAX_ENUM_NODES THEN
      BEGIN
        nenum_nodes := nenum_nodes + 1;
        enum_nodes[nenum_nodes] := node;
        enum_node_ids[nenum_nodes] := aux;
      END;
      names_arr := GetObj(node, 'values');
      FOR ni := 0 TO cJSON_GetArraySize(names_arr) - 1 DO
      BEGIN
        nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, ni)));
        DeclareName(nm, DECL_OTHER);
        bound_si := DefineSymbol(nm, 'CONST', TK_ENUM, aux, 0, 0, 0);
      END;
    END;
  END
  ELSE IF nt = 'SetType' THEN
  BEGIN
    base_node := GetObj(node, 'base');
    ResolveTypeExpr(base_node, inner_tk, inner_aux, inner_aux2, inner_aux3, inner_idx);
    IF NOT IsOrdinal(inner_tk) THEN
      AddError('SET OF <base> requires an ordinal base type')
    ELSE
      CheckSetBaseRange(base_node, inner_tk, inner_aux);
    tk := TK_SET;
    aux := inner_tk;
  END;
END;

PROCEDURE ResolveTypeExpr(node: ADRMEM; VAR tk, aux, aux2, aux3, idx_tk: INTEGER);
{ Every expression inside a type -- a subrange or array bound, a VECTOR
  lane count -- is a constant expression, so a call there is the intrinsic
  (UserDeclarationShadows), as codegen's FoldConstInt folds it. }
BEGIN
  const_expr_level := const_expr_level + 1;
  ResolveTypeExprBody(node, tk, aux, aux2, aux3, idx_tk);
  const_expr_level := const_expr_level - 1;
END;

BEGIN
END.
