{ Implementations for cg_symbols. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
IMPLEMENTATION OF cg_symbols;

VAR
  { ValidateInitckReads' enclosing WITH targets, innermost last: each one's
    record type (0 when not evident before lowering) and whether its fields
    are tracked storage (CodegenWithStmt binds them to field shadows). }
  initck_with_rec: ARRAY [1..64] OF INTEGER;
  initck_with_tracked: ARRAY [1..64] OF BOOLEAN;
  initck_with_top: INTEGER32;
  { A full proof table merely stops optimizing. Reset for each routine. }
  initck_proven_nodes: ARRAY [1..4096] OF ADRMEM;
  initck_proven_syms: ARRAY [1..4096] OF INTEGER32;
  initck_nproven: INTEGER32;

{ ============================ symbol table ============================== }

PROCEDURE PushScope;
{ Marks every table, not just symbols: a routine, CONST or TYPE name declared inside
  this scope is no more visible after it ends than a variable is. A
  routine's entry is written before its own body pushes a scope, so a
  routine always survives its own PopScope and only its nested children
  are discarded. }
BEGIN
  scope_top := scope_top + 1;
  scope_stack[scope_top] := nsymbols;
  routine_scope_stack[scope_top] := nroutines;
  const_scope_stack[scope_top] := nconsts;
  type_name_scope_stack[scope_top] := ntype_names;
END;

PROCEDURE PopScope;
BEGIN
  nsymbols := scope_stack[scope_top];
  nroutines := routine_scope_stack[scope_top];
  nconsts := const_scope_stack[scope_top];
  ntype_names := type_name_scope_stack[scope_top];
  scope_top := scope_top - 1;
END;

FUNCTION CurScopeBase: INTEGER32;
BEGIN
  IF scope_top = 0 THEN CurScopeBase := 0
  ELSE CurScopeBase := scope_stack[scope_top];
END;

FUNCTION InitckEnabled(node: ADRMEM): BOOLEAN;
BEGIN
  { Missing/legacy snapshots opt out; GetBool requires JSON true. }
  InitckEnabled := GetBool(GetObj(node, 'read_flags'), 'INITCK');
END;

FUNCTION InitckDeviceValueBuiltin(nm: Str255): BOOLEAN;
{ Host-side device runtime builtins take only values (sizes, geometry,
  device handles, kernel actuals copied into launch cells, raw host
  addresses): each operand is an ordinary read. Device memory is untracked;
  host storage a device copy or kernel writes is reached only through a
  raw address, whose ADR released it. }
BEGIN
  InitckDeviceValueBuiltin := (nm = 'LAUNCH') OR (nm = 'DEVALLOC') OR
    (nm = 'DEVCOPYTO') OR (nm = 'DEVCOPYFROM') OR (nm = 'DEVFREE');
END;

FUNCTION InitckShadowSize(tid: INTEGER): INTEGER32;
{ How many i1 INITCK states a value of type tid carries: one per scalar leaf
  of exact INTEGER/BOOLEAN/CHAR, raw address (ADRMEM), plain typed pointer
  or SUPER ARRAY descriptor type, through fixed ARRAYs and RECORDs. 0 when
  any part of the representation is outside the tracked slice (another
  scalar, an ADS pointer, string, set, vector, file or SUPER ARRAY): such an object
  stays wholly untracked. Variant alternatives get disjoint states although
  their storage overlaps; see InitckFieldShadowOffset. }
VAR
  fi: INTEGER;
  n, s: INTEGER32;
  wide_n: INTEGER64;
  bad: BOOLEAN;
BEGIN
  n := 0;
  IF InitckTrackedTk(tid) THEN n := 1
  ELSE IF TypeKind(tid) = TK_ARRAY THEN
  BEGIN
    IF NOT types[tid].is_super THEN
    BEGIN
      { More leaves than INTEGER32 can count is outside the tracked slice. }
      wide_n := InitckShadowSize(types[tid].elem_tid);
      wide_n := wide_n * (types[tid].hi - types[tid].lo + 1);
      IF wide_n <= 2147483647 THEN n := RETYPE(INTEGER32, wide_n);
    END;
  END
  ELSE IF TypeKind(tid) = TK_RECORD THEN
  BEGIN
    bad := FALSE;
    FOR fi := 1 TO nfields DO
      IF fields[fi].rec_tid = tid THEN
      BEGIN
        s := InitckShadowSize(fields[fi].field_tid);
        IF s = 0 THEN bad := TRUE;
        n := n + s;
      END;
    IF bad THEN n := 0;
  END;
  InitckShadowSize := n;
END;

FUNCTION InitckShadowTy(tid: INTEGER): ADRMEM;
{ LLVM type of tid's shadow: i1 for a scalar leaf, an array of element
  shadows for an ARRAY (so an INDEX selector reuses the data GEP's checked
  offset), and a flat i1 array for a RECORD (fields at
  InitckFieldShadowOffset). An i1 occupies one byte in memory, so a shadow
  of InitckShadowSize(tid) leaves is exactly that many bytes. }
BEGIN
  IF InitckTrackedTk(tid) THEN InitckShadowTy := i1ty
  ELSE IF TypeKind(tid) = TK_ARRAY THEN
    InitckShadowTy := LLVMArrayType(InitckShadowTy(types[tid].elem_tid),
                                    types[tid].hi - types[tid].lo + 1)
  ELSE InitckShadowTy := LLVMArrayType(i1ty, InitckShadowSize(tid));
END;

FUNCTION InitckFieldShadowOffset(fi: INTEGER): INTEGER32;
{ A record field's first leaf within its record's flat shadow: fields keep
  declaration order (fixed fields, tag, then each variant arm's fields), and
  every field owns its own leaves. Overlapping variant storage therefore
  never shares state: a write through one alternative neither initializes
  nor invalidates another (the logical-field model, not a byte model). }
VAR
  k: INTEGER;
  off: INTEGER32;
BEGIN
  off := 0;
  FOR k := 1 TO fi - 1 DO
    IF fields[k].rec_tid = fields[fi].rec_tid THEN
      off := off + InitckShadowSize(fields[k].field_tid);
  InitckFieldShadowOffset := off;
END;

FUNCTION InitckSelectedTid(tid: INTEGER; selectors: ADRMEM): INTEGER;
{ Static type reached by INDEX/FIELD selectors from a shadowed type, or 0
  when a selector leaves the shadowed representation (DEREF, LSTRING LEN) or
  the root is not shadowed at all. }
VAR
  si: INTEGER32;
  sel: ADRMEM;
  kind: Str255;
  fi: INTEGER;
BEGIN
  IF InitckShadowSize(tid) = 0 THEN tid := 0;
  FOR si := 0 TO ArrSize(selectors) - 1 DO
    IF tid <> 0 THEN
    BEGIN
      sel := ArrItem(selectors, si);
      kind := GetStr(sel, 'kind');
      IF (kind = 'INDEX') AND (TypeKind(tid) = TK_ARRAY) THEN
        tid := types[tid].elem_tid
      ELSE IF (kind = 'FIELD') AND (TypeKind(tid) = TK_RECORD) THEN
      BEGIN
        fi := LookupField(tid, GetStr(sel, 'index_or_field'));
        IF fi = 0 THEN tid := 0 ELSE tid := fields[fi].field_tid;
      END
      ELSE tid := 0;
    END;
  InitckSelectedTid := tid;
END;

FUNCTION InitckOwnTid(tid: INTEGER; selectors: ADRMEM; VAR via_ptr: BOOLEAN): INTEGER;
{ Like InitckSelectedTid, but a DEREF of a tracked pointer leaf ends the
  root's own storage: that leaf is read (via_ptr) and the selectors after it
  name heap storage, never the root's. }
VAR
  si: INTEGER32;
  sel: ADRMEM;
  kind: Str255;
  fi: INTEGER;
BEGIN
  via_ptr := FALSE;
  IF InitckShadowSize(tid) = 0 THEN tid := 0;
  si := 0;
  WHILE (tid <> 0) AND (NOT via_ptr) AND (si < ArrSize(selectors)) DO
  BEGIN
    sel := ArrItem(selectors, si);
    kind := GetStr(sel, 'kind');
    IF (kind = 'INDEX') AND (TypeKind(tid) = TK_ARRAY) THEN
      tid := types[tid].elem_tid
    ELSE IF (kind = 'FIELD') AND (TypeKind(tid) = TK_RECORD) THEN
    BEGIN
      fi := LookupField(tid, GetStr(sel, 'index_or_field'));
      IF fi = 0 THEN tid := 0 ELSE tid := fields[fi].field_tid;
    END
    ELSE IF (kind = 'DEREF') AND InitckPointerTk(tid) THEN via_ptr := TRUE
    ELSE tid := 0;
    si := si + 1;
  END;
  InitckOwnTid := tid;
END;

FUNCTION InitckIntText(n: INTEGER32): Str255;
VAR
  tmp, t: Str255;
  i: INTEGER;
BEGIN
  tmp := '';
  t := '';
  IF n < 0 THEN
  BEGIN
    AppendChar(t, '-');
    n := -n;
  END;
  AppendChar(tmp, CHR(RETYPE(INTEGER, ORD('0') + n MOD 10)));
  n := n DIV 10;
  WHILE n > 0 DO
  BEGIN
    AppendChar(tmp, CHR(RETYPE(INTEGER, ORD('0') + n MOD 10)));
    n := n DIV 10;
  END;
  FOR i := ORD(tmp[0]) DOWNTO 1 DO AppendChar(t, tmp[i]);
  InitckIntText := t;
END;

PROCEDURE InitckBoundaryAt(category: Str255; node: ADRMEM);
{ Reject an enabled read INITCK does not cover, before any IR is published:
  `INITCK unsupported boundary: <category>`, followed by the consuming
  token's ` at line L column C` when the node carries it. DEVICE compilands
  (CPU-targeted or NVPTX) have no INITCK state at all: host instrumentation
  covers nothing there, so every enabled read in one reports that, whatever
  storage it names. }
VAR
  msg: Str255;
  line, column: INTEGER32;
BEGIN
  IF is_device_compiland THEN category := 'DEVICE code';
  msg := category;
  IF node <> NIL THEN
  BEGIN
    line := GetInt(GetObj(node, 'read_location'), 'line');
    column := GetInt(GetObj(node, 'read_location'), 'column');
    IF (line > 0) AND (column > 0) THEN
    BEGIN
      CONCAT(msg, ' at line ');
      CONCAT(msg, InitckIntText(line));
      CONCAT(msg, ' column ');
      CONCAT(msg, InitckIntText(column));
    END;
  END;
  AbortWith2('INITCK unsupported boundary: ', msg);
END;

FUNCTION InitckSymCategory(symi: INTEGER32): Str255;
{ Why a routine-visible symbol has no state where it is read: it belongs
  to an enclosing scope (a global, or a capture), its type is outside the
  tracked slice, or the escape prepass disqualified it for the routine. }
BEGIN
  IF symi <= initck_scope_base THEN InitckSymCategory := 'global or captured storage'
  ELSE IF InitckShadowSize(symbols[symi].tk) = 0 THEN InitckSymCategory := 'untracked type'
  ELSE InitckSymCategory := 'escaped local or formal';
END;

FUNCTION InitckDesigPrefix(node: ADRMEM; nsel: INTEGER32): Str255;
{ Diagnostic spelling of a designator's root and first nsel selectors: field
  names verbatim, `^` for a dereference, an index shown when it is a literal
  or a plain name, else as `...`. }
VAR
  t, part: Str255;
  si: INTEGER32;
  sel, ix: ADRMEM;
BEGIN
  t := GetStr(node, 'name');
  FOR si := 0 TO nsel - 1 DO
  BEGIN
    sel := ArrItem(GetObj(node, 'selectors'), si);
    IF GetStr(sel, 'kind') = 'DEREF' THEN AppendChar(t, '^')
    ELSE IF GetStr(sel, 'kind') = 'FIELD' THEN
    BEGIN
      part := GetStr(sel, 'index_or_field');
      AppendChar(t, '.');
      CONCAT(t, part);
    END
    ELSE IF GetStr(sel, 'kind') = 'INDEX' THEN
    BEGIN
      ix := GetObj(sel, 'index_or_field');
      IF NodeType(ix) = 'IntLiteral' THEN part := InitckIntText(GetInt(ix, 'value'))
      ELSE IF (NodeType(ix) = 'Identifier') OR
        ((NodeType(ix) = 'Designator') AND (ArrSize(GetObj(ix, 'selectors')) = 0)) THEN
        part := GetStr(ix, 'name')
      ELSE part := '...';
      AppendChar(t, '[');
      CONCAT(t, part);
      AppendChar(t, ']');
    END;
  END;
  InitckDesigPrefix := t;
END;

FUNCTION InitckDesigText(node: ADRMEM): Str255;
BEGIN
  InitckDesigText := InitckDesigPrefix(node, ArrSize(GetObj(node, 'selectors')));
END;

FUNCTION NamesInclude(arr: ADRMEM; uname: Str255): BOOLEAN;
{ Does a JSON array of identifier strings contain uname (case-insensitive)? }
VAR
  i: INTEGER32;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  FOR i := 0 TO ArrSize(arr) - 1 DO
    IF UpperStr(CStrToStr255(cJSON_GetStringValue(ArrItem(arr, i)))) = uname THEN
      found := TRUE;
  NamesInclude := found;
END;

FUNCTION RoutineRedeclares(decl: ADRMEM; uname: Str255): BOOLEAN;
{ Does a nested routine declare uname itself (a formal, or any declaration in
  its own block)? Then every use of the name inside it, including in deeper
  routines, is not the enclosing local. Unrecognized declaration shapes only
  lose precision: the caller then treats a mention as a capture. }
VAR
  i: INTEGER32;
  found: BOOLEAN;
  params, decls, d: ADRMEM;
BEGIN
  found := FALSE;
  params := GetObj(decl, 'params');
  FOR i := 0 TO ArrSize(params) - 1 DO
    IF NamesInclude(GetObj(ArrItem(params, i), 'names'), uname) THEN found := TRUE;
  decls := GetObj(GetObj(decl, 'body'), 'decls');
  FOR i := 0 TO ArrSize(decls) - 1 DO
  BEGIN
    d := ArrItem(decls, i);
    IF NamesInclude(GetObj(d, 'names'), uname) THEN found := TRUE;
    IF UpperStr(GetStr(d, 'name')) = uname THEN found := TRUE;
  END;
  RoutineRedeclares := found;
END;

FUNCTION StaticDesigTid(tid: INTEGER; selectors: ADRMEM): INTEGER;
{ The type a designator's selectors reach from a root of type tid, or 0 when
  it is not evident before lowering. }
VAR
  si: INTEGER32;
  sel: ADRMEM;
  kind: Str255;
  fi: INTEGER;
BEGIN
  FOR si := 0 TO ArrSize(selectors) - 1 DO
    IF tid <> 0 THEN
    BEGIN
      sel := ArrItem(selectors, si);
      kind := GetStr(sel, 'kind');
      IF (kind = 'INDEX') AND (TypeKind(tid) = TK_ARRAY) THEN tid := types[tid].elem_tid
      ELSE IF (kind = 'DEREF') AND (TypeKind(tid) = TK_POINTER) THEN tid := types[tid].elem_tid
      ELSE IF (kind = 'FIELD') AND (TypeKind(tid) = TK_RECORD) THEN
      BEGIN
        fi := LookupField(tid, GetStr(sel, 'index_or_field'));
        IF fi = 0 THEN tid := 0 ELSE tid := fields[fi].field_tid;
      END
      ELSE tid := 0;
    END;
  StaticDesigTid := tid;
END;

FUNCTION WithTargetTid(t: ADRMEM; in_with: BOOLEAN): INTEGER;
{ A WITH target's record type when evident before lowering: its root is a
  routine-visible variable (not a field bound by an enclosing WITH, which may
  shadow it) and its selectors resolve statically. 0 otherwise. }
VAR
  symi: INTEGER32;
  tid: INTEGER;
BEGIN
  tid := 0;
  IF NOT in_with THEN
  BEGIN
    symi := LookupSym(GetStr(t, 'name'));
    IF symi <> 0 THEN tid := StaticDesigTid(symbols[symi].tk, GetObj(t, 'selectors'));
  END;
  IF TypeKind(tid) <> TK_RECORD THEN tid := 0;
  WithTargetTid := tid;
END;

FUNCTION WithFieldBinding(targets: ADRMEM; uname: Str255; in_with: BOOLEAN): INTEGER;
{ How a WITH body resolves uname: 0 = no target has such a field, so it is
  still the routine's symbol; 1 = some target definitely binds it as a field;
  2 = unknown (a target whose record type is not evident, see WithTargetTid).
  Field shadowing follows CodegenWithStmt. }
VAR
  i, fi: INTEGER32;
  rec: INTEGER;
  res: INTEGER;
BEGIN
  res := 0;
  FOR i := 0 TO ArrSize(targets) - 1 DO
  BEGIN
    rec := WithTargetTid(ArrItem(targets, i), in_with);
    IF rec = 0 THEN
    BEGIN
      IF res = 0 THEN res := 2;
    END
    ELSE
      FOR fi := 1 TO nfields DO
        IF fields[fi].rec_tid = rec THEN
          IF UpperStr(fields[fi].fname) = uname THEN res := 1;
  END;
  WithFieldBinding := res;
END;

FUNCTION InitckLocalEscapes(node: ADRMEM; name: Str255; tid: INTEGER;
                            unsafe, opaque, in_with, whole_ok: BOOLEAN): BOOLEAN;
{ Can the tracked slot `name` (of type tid) be reached by anything but a
  modeled producer or read? unsafe: this subtree names storage through an
  alias or untracked effect (ADR, a VAR binding, a builtin); opaque: every
  mention may be other storage or a capture, so any mention escapes;
  whole_ok: node itself is in a modeled aggregate copy context (assignment
  target/source, value actual), where naming an aggregate whole transfers
  its leaf states. Children never inherit whole_ok. }
VAR
  nt, nm, uname: Str255;
  i, ri, k: INTEGER32;
  found, arg_unsafe, arg_whole, via_ptr: BOOLEAN;
  args, targets, selectors, sel, arg: ADRMEM;
  binding, sel_tid: INTEGER;
  saved_scan: BOOLEAN;
BEGIN
  nt := NodeType(node);
  nm := UpperStr(GetStr(node, 'name'));
  uname := UpperStr(name);
  found := FALSE;
  { ADR names a routine symbol's whole storage without reading it. Lowering
    releases every leaf of it as initialized at that point (raw writes
    through the address are not modeled) and the slot stays tracked. A
    WITH-bound field's address still escapes: raw writes from it may run
    into its siblings. }
  IF nt = 'AdrExpr' THEN
  BEGIN
    IF initck_field_scan THEN unsafe := TRUE
    ELSE
    BEGIN
      InitckLocalEscapes := opaque AND (nm = uname);
      RETURN;
    END;
  END;
  { No static link exists, so a nested routine can name the enclosing local
    only by capturing it (unsupported by this compiler): any mention is an
    escape, unless the routine redeclares the name for its own storage. }
  IF (nt = 'ProcDecl') OR (nt = 'FuncDecl') THEN
  BEGIN
    IF NOT RoutineRedeclares(node, uname) THEN
      found := InitckLocalEscapes(GetObj(node, 'body'), name, tid, TRUE, TRUE, FALSE, FALSE);
    InitckLocalEscapes := found;
    RETURN;
  END;
  { WITH binds its targets' fields over the body. Where the name is not such
    a field it remains this local, a direct slot even inside WITH's scope;
    where it definitely is one, the body never mentions the local. }
  IF nt = 'WithStmt' THEN
  BEGIN
    targets := GetObj(node, 'targets');
    FOR i := 0 TO ArrSize(targets) - 1 DO
    BEGIN
      arg := ArrItem(targets, i);
      sel_tid := 0;
      IF (UpperStr(GetStr(arg, 'name')) = uname) AND NOT (unsafe OR opaque OR in_with) THEN
        sel_tid := InitckSelectedTid(tid, GetObj(arg, 'selectors'));
      IF TypeKind(sel_tid) = TK_RECORD THEN
      BEGIN
        { WITH over this slot's own (sub-)record binds each field to the
          field's shadow (CodegenWithStmt): its index operands are reads,
          and every field must stay modeled storage throughout the body. }
        selectors := GetObj(arg, 'selectors');
        FOR k := 0 TO ArrSize(selectors) - 1 DO
        BEGIN
          sel := ArrItem(selectors, k);
          IF GetStr(sel, 'kind') = 'INDEX' THEN
            IF InitckLocalEscapes(GetObj(sel, 'index_or_field'), name, tid,
                                  FALSE, FALSE, in_with, FALSE) THEN found := TRUE;
        END;
        saved_scan := initck_field_scan;
        initck_field_scan := TRUE;
        FOR k := 1 TO nfields DO
          IF fields[k].rec_tid = sel_tid THEN
            IF InitckLocalEscapes(GetObj(node, 'body'), fields[k].fname, fields[k].field_tid,
                                  FALSE, FALSE, TRUE, FALSE) THEN found := TRUE;
        initck_field_scan := saved_scan;
      END
      ELSE IF InitckLocalEscapes(arg, name, tid, TRUE, opaque, in_with, FALSE) THEN found := TRUE;
    END;
    binding := WithFieldBinding(targets, uname, in_with);
    IF binding = 0 THEN
      IF InitckLocalEscapes(GetObj(node, 'body'), name, tid, unsafe, opaque, TRUE, FALSE) THEN found := TRUE;
    IF binding = 2 THEN
      IF InitckLocalEscapes(GetObj(node, 'body'), name, tid, TRUE, TRUE, TRUE, FALSE) THEN found := TRUE;
    InitckLocalEscapes := found;
    RETURN;
  END;
  { Static bound queries name a type, not storage. UPPER of a dereferenced
    SUPER ARRAY pointer reads that descriptor (walked below). }
  IF (nt = 'UpperExpr') OR (nt = 'LowerExpr') THEN
  BEGIN
    selectors := GetObj(GetObj(node, 'operand'), 'selectors');
    IF ArrSize(selectors) = 0 THEN
    BEGIN
      InitckLocalEscapes := FALSE;
      RETURN;
    END;
    IF GetStr(ArrItem(selectors, ArrSize(selectors) - 1), 'kind') <> 'DEREF' THEN
    BEGIN
      InitckLocalEscapes := FALSE;
      RETURN;
    END;
  END;
  { Inspect the WHOLE body before emitting any guard, including escapes
    after a checked read. A value actual of a user routine is an ordinary
    read at the call site (checked, or its state transported); a VAR/CONST
    actual aliases the caller's storage and still disqualifies it. }
  IF (nt = 'ProcCallStmt') OR (nt = 'FuncCall') THEN
  BEGIN
    ri := LookupRoutine(nm);
    IF ri <> 0 THEN
    BEGIN
      args := GetObj(node, 'args');
      FOR i := 0 TO ArrSize(args) - 1 DO
      BEGIN
        { A tracked VAR/CONST formal of a transporting routine shares the
          actual's state (CodegenCallCommon publishes it); one of a [C]
          routine initializes exactly the bound storage at the call. Any
          other reference binding leaves the storage to untracked writes. }
        arg := ArrItem(args, i);
        arg_unsafe := unsafe;
        arg_whole := FALSE;
        IF i < routines[ri].nparams THEN
          IF routines[ri].param_is_var[i + 1] THEN
          BEGIN
            { The binding names the actual's own storage: a direct slot, a
              selected leaf, or a whole or sub-aggregate. }
            IF InitckShadowSize(routines[ri].param_tk[i + 1]) = 0 THEN
              arg_unsafe := TRUE
            ELSE IF InitckTransports(ri) OR
                    (routines[ri].is_c AND NOT is_device_compiland) THEN
              arg_whole := TRUE
            ELSE arg_unsafe := TRUE;
          END
          { A value aggregate actual is a checked or state-carrying copy. }
          ELSE arg_whole := TRUE;
        IF InitckLocalEscapes(arg, name, tid, arg_unsafe, opaque, in_with, arg_whole) THEN found := TRUE;
      END;
      InitckLocalEscapes := found;
      RETURN;
    END;
    { Other builtins conservatively disqualify their operands until effect
      contracts exist. READ/READLN name destinations (producers, lowered in
      cg_io). FOR control is a producer lowered in CodegenForStmt. NEW's
      pointer is a producer and DISPOSE's a read (CodegenProcCallStmt);
      their bound/tag operands are reads. UNSAFERAW reads its descriptor
      and UNSAFESUPER its raw pointer and bounds (its type name is not
      storage). }
    IF (nm <> 'WRITE') AND (nm <> 'WRITELN') AND (nm <> 'ORD') AND
       (nm <> 'CHR') AND (nm <> 'ODD') AND (nm <> 'ABS') AND
       (nm <> 'READ') AND (nm <> 'READLN') AND (nm <> 'NEW') AND
       (nm <> 'DISPOSE') AND (nm <> 'UNSAFERAW') AND (nm <> 'UNSAFESUPER') AND
       NOT InitckDeviceValueBuiltin(nm) THEN
      unsafe := TRUE;
  END;
  { An assignment's target and source may each name tracked storage whole:
    the copy transfers leaf states (CodegenAssignStmt). }
  IF nt = 'AssignStmt' THEN
  BEGIN
    found := InitckLocalEscapes(GetObj(node, 'target'), name, tid, unsafe, opaque, in_with, TRUE);
    IF InitckLocalEscapes(GetObj(node, 'expr'), name, tid, unsafe, opaque, in_with, TRUE) THEN
      found := TRUE;
    InitckLocalEscapes := found;
    RETURN;
  END;
  { A component selected by INDEX/FIELD down to a tracked scalar leaf is
    modeled storage: its reads are guarded and its writes publish its own
    leaf. Naming an aggregate or sub-aggregate whole is modeled only in a
    copy context; selecting through an alias/effect is not modeled. Index
    operands are independent value reads wherever the designator appears. }
  IF nt = 'Designator' THEN
  BEGIN
    selectors := GetObj(node, 'selectors');
    IF ArrSize(selectors) <> 0 THEN
    BEGIN
      IF nm = uname THEN
      BEGIN
        { Dereferencing a tracked pointer leaf only reads that leaf: what
          the rest of the designator selects (and any alias or effect it
          reaches) is heap storage, not this slot. }
        sel_tid := InitckOwnTid(tid, selectors, via_ptr);
        IF opaque OR (sel_tid = 0) THEN found := TRUE
        ELSE IF via_ptr THEN found := FALSE
        ELSE IF unsafe THEN found := TRUE
        ELSE IF NOT (InitckTrackedTk(sel_tid) OR whole_ok) THEN found := TRUE;
      END;
      FOR i := 0 TO ArrSize(selectors) - 1 DO
      BEGIN
        sel := ArrItem(selectors, i);
        IF GetStr(sel, 'kind') = 'INDEX' THEN
          IF InitckLocalEscapes(GetObj(sel, 'index_or_field'), name, tid,
                                opaque, opaque, in_with, FALSE) THEN found := TRUE;
      END;
      InitckLocalEscapes := found;
      RETURN;
    END;
  END;
  IF (nt = 'Identifier') OR (nt = 'Designator') THEN
    IF (nm = uname) AND NOT (InitckTrackedTk(tid) OR whole_ok) THEN found := TRUE;
  IF (unsafe OR opaque) AND (nm = uname) THEN found := TRUE;
  FOR i := 0 TO ArrSize(node) - 1 DO
    IF InitckLocalEscapes(ArrItem(node, i), name, tid, unsafe, opaque, in_with, FALSE) THEN found := TRUE;
  InitckLocalEscapes := found;
END;

FUNCTION InitckWithField(nm: Str255; VAR tracked: BOOLEAN): INTEGER;
{ Inside the WITH bodies being validated: the type of the field nm names, or
  0 when nm is not a field of an evident target (it is then resolved like
  any name). tracked: the field is tracked storage. Stops at a target whose
  type is not evident, since nm may or may not be one of its fields. }
VAR
  k: INTEGER32;
  fi, res: INTEGER;
BEGIN
  res := 0;
  tracked := FALSE;
  k := initck_with_top;
  WHILE k > 0 DO
  BEGIN
    IF initck_with_rec[k] = 0 THEN k := 0
    ELSE
    BEGIN
      fi := LookupField(initck_with_rec[k], nm);
      IF fi <> 0 THEN
      BEGIN
        res := fields[fi].field_tid;
        tracked := initck_with_tracked[k];
        k := 0;
      END
      ELSE k := k - 1;
    END;
  END;
  InitckWithField := res;
END;

CONST
  { ValidateInitckReads contexts: how the storage a designator selects is used
    besides any read. }
  INITCK_CTX_PLAIN = 0;  { modeled: a value read, a producer, a copy, a
                           tracked VAR/CONST binding }
  INITCK_CTX_EFFECT = 1; { handed to an unmodeled alias or effect: an ADR
                           operand, a VAR/CONST actual of a [C] routine or of
                           an untracked formal type, a non-scalar builtin }
  INITCK_CTX_IO = 2;     { a READ/READLN/WRITE/WRITELN item: modeled only
                           for a tracked scalar leaf }

PROCEDURE ValidateInitckReads(node: ADRMEM; read_value: BOOLEAN; ctx: INTEGER); FORWARD;

FUNCTION InitckWithUnknown: BOOLEAN;
{ Is some enclosing WITH target's record type not evident? A name may then
  be one of its fields, whatever routine symbol it matches. }
VAR
  k: INTEGER32;
  unknown: BOOLEAN;
BEGIN
  unknown := FALSE;
  FOR k := 1 TO initck_with_top DO
    IF initck_with_rec[k] = 0 THEN unknown := TRUE;
  InitckWithUnknown := unknown;
END;

FUNCTION InitckHeapTracked(ptr_tid: INTEGER): BOOLEAN;
{ Does the referent of a pointer of this type carry heap state? A plain host
  pointer whose target type is tracked (NEW registers it, a dereference
  looks it up). }
BEGIN
  InitckHeapTracked := FALSE;
  IF InitckPointerTk(ptr_tid) AND NOT IsHostDescriptor(ptr_tid) AND
     NOT is_device_compiland THEN
    InitckHeapTracked := InitckShadowSize(types[ptr_tid].elem_tid) > 0;
END;

FUNCTION InitckSuperHeapTracked(ptr_tid: INTEGER): BOOLEAN;
{ Do the elements a host SUPER ARRAY descriptor locates carry heap state?
  Those NEW allocated, when the element type is tracked. }
BEGIN
  InitckSuperHeapTracked := FALSE;
  IF IsHostDescriptor(ptr_tid) AND NOT is_device_compiland THEN
    InitckSuperHeapTracked := InitckShadowSize(types[types[ptr_tid].elem_tid].elem_tid) > 0;
END;

FUNCTION ValidateInitckDesignator(node: ADRMEM; read_value: BOOLEAN; ctx: INTEGER;
                                  VAR final_tid: INTEGER): BOOLEAN;
{ An Identifier/Designator: index operands are reads; each DEREF of a
  pointer reads the pointer storage selected so far (checked at the DEREF
  selector's own snapshot); the designator's own snapshot governs the read
  of the storage it finally selects, when read_value. An enabled read of
  storage without shadow state is rejected with the category of where that
  storage lives. Returns whether the selected storage is tracked, and its
  type (0 when not evident).

  Heap state belongs to an allocation, not to a routine, so a referent that
  reaches an unmodeled alias or effect cannot be disqualified statically:
  such a designator is marked `initck_release` and lowering releases the
  referent its last DEREF reaches (it then reads as untracked storage). }
VAR
  nm, kind, category: Str255;
  symi, si: INTEGER32;
  selectors, sel: ADRMEM;
  tracked, deref, file_ctl: BOOLEAN;
  tid: INTEGER;
  fi: INTEGER;
BEGIN
  nm := GetStr(node, 'name');
  selectors := GetObj(node, 'selectors');
  deref := FALSE;
  file_ctl := FALSE;
  tid := InitckWithField(nm, tracked);
  { A WITH-bound field without state: the WITH target is storage without
    state (its record holds an untracked leaf, or it is a global, a released
    heap referent, a disqualified local). }
  category := 'untracked WITH target';
  IF (tid = 0) AND InitckWithUnknown THEN
  BEGIN
    { Under a WITH whose target type is not evident, the name may be one
      of its fields. }
    tracked := FALSE;
    category := 'unresolved WITH target';
  END
  ELSE IF tid = 0 THEN
  BEGIN
    symi := LookupSym(nm);
    IF symi <> 0 THEN
    BEGIN
      tid := symbols[symi].tk;
      tracked := InitckTracked(symi);
      category := InitckSymCategory(symi);
    END
    ELSE
    BEGIN
      { A niladic call: a value producer whose result state is transported,
        not a read of storage; selecting from its result is not modeled. }
      IF read_value AND InitckEnabled(node) THEN
      BEGIN
        IF UpperStr(nm) = 'RESULT' THEN
          InitckBoundaryAt('function result', node);
        IF ArrSize(selectors) <> 0 THEN
          InitckBoundaryAt('selected storage', node);
      END;
      FOR si := 0 TO ArrSize(selectors) - 1 DO
        ValidateInitckReads(ArrItem(selectors, si), TRUE, INITCK_CTX_PLAIN);
      final_tid := 0;
      ValidateInitckDesignator := FALSE;
      RETURN;
    END;
  END;
  FOR si := 0 TO ArrSize(selectors) - 1 DO
  BEGIN
    sel := ArrItem(selectors, si);
    kind := GetStr(sel, 'kind');
    IF kind = 'INDEX' THEN
    BEGIN
      ValidateInitckReads(GetObj(sel, 'index_or_field'), TRUE, INITCK_CTX_PLAIN);
      IF TypeKind(tid) = TK_ARRAY THEN
        { A SUPER ARRAY exists only behind a descriptor's DEREF, which
          decided whether its elements are tracked. }
        tid := types[tid].elem_tid
      ELSE
      BEGIN
        tracked := FALSE;
        tid := 0;
      END;
    END
    ELSE IF kind = 'FIELD' THEN
    BEGIN
      fi := 0;
      { F.ERRS, F.TRAP: file control state, initialized with the file
        (NEWFQQ), not Pascal data. }
      IF TypeKind(tid) = TK_FILE THEN file_ctl := TRUE;
      IF TypeKind(tid) = TK_RECORD THEN fi := LookupField(tid, GetStr(sel, 'index_or_field'));
      IF fi = 0 THEN
      BEGIN
        tracked := FALSE;
        tid := 0;
      END
      ELSE tid := fields[fi].field_tid;
    END
    ELSE IF (kind = 'DEREF') AND (TypeKind(tid) = TK_FILE) THEN
    BEGIN
      { A file buffer F^ (F is not read as a value): per-leaf state beside
        the buffer when its component type is tracked (InitFileStorage). }
      tid := types[tid].elem_tid;
      tracked := (InitckShadowSize(tid) > 0) AND NOT is_device_compiland;
      category := 'file buffer';
      deref := TRUE;
    END
    ELSE
    BEGIN
      { Reading the pointer that locates the referent. }
      IF InitckEnabled(sel) AND NOT tracked THEN
        InitckBoundaryAt(category, sel);
      deref := TRUE;
      category := 'heap storage';
      IF TypeKind(tid) = TK_POINTER THEN
      BEGIN
        tracked := InitckHeapTracked(tid) OR InitckSuperHeapTracked(tid);
        tid := types[tid].elem_tid;
      END
      ELSE
      BEGIN
        tracked := FALSE;
        tid := 0;
      END;
    END;
  END;
  IF deref THEN
    IF (ctx = INITCK_CTX_EFFECT) OR
       ((ctx = INITCK_CTX_IO) AND NOT InitckTrackedTk(tid)) THEN
    BEGIN
      IF NOT HasKey(node, 'initck_release') THEN AddBoolField(node, 'initck_release', TRUE);
      tracked := FALSE;
    END;
  { Naming a file (RESET(f), WRITELN(f, ...)) or reading its control fields
    consumes file state the file's initialization set, not Pascal data. }
  IF TypeKind(tid) = TK_FILE THEN file_ctl := TRUE;
  IF read_value AND InitckEnabled(node) AND NOT tracked AND NOT file_ctl THEN
    InitckBoundaryAt(category, node);
  final_tid := tid;
  ValidateInitckDesignator := tracked;
END;

PROCEDURE ValidateInitckReads(node: ADRMEM; read_value: BOOLEAN; ctx: INTEGER);
VAR
  nt, nm: Str255;
  i, nsel, ri, saved_top: INTEGER32;
  selectors, args, t, body: ADRMEM;
  arg_reads, base_tracked: BOOLEAN;
  rec_tid: INTEGER;
  k: INTEGER32;
  arg_ctx: INTEGER;
BEGIN
  nt := NodeType(node);
  IF (nt = 'SizeofExpr') OR (nt = 'LowerExpr') THEN RETURN;
  { ADR names storage without reading it; its selection operands are still
    reads, and heap storage it reaches escapes. }
  IF nt = 'AdrExpr' THEN
  BEGIN
    read_value := FALSE;
    ctx := INITCK_CTX_EFFECT;
  END;
  IF nt = 'UpperExpr' THEN
  BEGIN
    selectors := GetObj(GetObj(node, 'operand'), 'selectors');
    nsel := ArrSize(selectors);
    IF nsel = 0 THEN RETURN;
    IF GetStr(ArrItem(selectors, nsel - 1), 'kind') <> 'DEREF' THEN RETURN;
    { UPPER(p^) reads the descriptor at its DEREF (and anything selecting
      it), never the elements. }
    ValidateInitckReads(GetObj(node, 'operand'), FALSE, INITCK_CTX_PLAIN);
    RETURN;
  END;
  IF nt = 'Selector' THEN
    IF GetStr(node, 'kind') <> 'DEREF' THEN
    BEGIN
      ValidateInitckReads(GetObj(node, 'index_or_field'), TRUE, INITCK_CTX_PLAIN);
      RETURN;
    END;
  IF nt = 'WriteArg' THEN
  BEGIN
    { An output item keeps its I/O context; width and precision are reads. }
    ValidateInitckReads(GetObj(node, 'expr'), TRUE, ctx);
    ValidateInitckReads(GetObj(node, 'width'), TRUE, INITCK_CTX_PLAIN);
    ValidateInitckReads(GetObj(node, 'precision'), TRUE, INITCK_CTX_PLAIN);
    RETURN;
  END;
  IF nt = 'AssignStmt' THEN
  BEGIN
    ValidateInitckReads(GetObj(node, 'target'), FALSE, INITCK_CTX_PLAIN);
    ValidateInitckReads(GetObj(node, 'expr'), TRUE, INITCK_CTX_PLAIN);
    RETURN;
  END;
  IF nt = 'ReturnStmt' THEN
  BEGIN
    { A function RETURN reads the result it publishes (InitckPublishResult). }
    IF InitckEnabled(node) AND (cur_func_name <> '') AND (cur_func_ret_state = NIL) THEN
      InitckBoundaryAt('function result', node);
    RETURN;
  END;
  IF nt = 'WithStmt' THEN
  BEGIN
    saved_top := initck_with_top;
    body := GetObj(node, 'body');
    FOR i := 0 TO ArrSize(GetObj(node, 'targets')) - 1 DO
    BEGIN
      t := ArrItem(GetObj(node, 'targets'), i);
      { The target's root: a field bound by an enclosing WITH, or a variable;
        under an enclosing target whose type is not evident, unknown too. }
      base_tracked := ValidateInitckDesignator(t, FALSE, ctx, rec_tid);
      IF TypeKind(rec_tid) <> TK_RECORD THEN rec_tid := 0;
      IF rec_tid = 0 THEN base_tracked := FALSE;
      { A WITH over a heap record binds its fields to the referent's state
        (CodegenWithStmt) only if every use of them in the body is modeled;
        otherwise the WITH releases the referent and binds untracked fields. }
      IF base_tracked AND HasKey(t, 'selectors') THEN
      BEGIN
        selectors := GetObj(t, 'selectors');
        nsel := ArrSize(selectors);
        FOR k := 0 TO nsel - 1 DO
          IF GetStr(ArrItem(selectors, k), 'kind') = 'DEREF' THEN
          BEGIN
            arg_reads := FALSE;
            initck_field_scan := TRUE;
            FOR ri := 1 TO nfields DO
              IF fields[ri].rec_tid = rec_tid THEN
                IF InitckLocalEscapes(body, fields[ri].fname, fields[ri].field_tid,
                                      FALSE, FALSE, TRUE, FALSE) THEN arg_reads := TRUE;
            initck_field_scan := FALSE;
            IF arg_reads THEN
            BEGIN
              IF NOT HasKey(t, 'initck_release') THEN AddBoolField(t, 'initck_release', TRUE);
              base_tracked := FALSE;
            END;
          END;
      END;
      IF initck_with_top >= 64 THEN AbortWith('codegen: WITH nested too deeply');
      initck_with_top := initck_with_top + 1;
      initck_with_rec[initck_with_top] := rec_tid;
      initck_with_tracked[initck_with_top] := base_tracked;
    END;
    ValidateInitckReads(body, TRUE, INITCK_CTX_PLAIN);
    initck_with_top := saved_top;
    RETURN;
  END;
  { A tracked root reaching here has only modeled mentions (the escape
    prepass disqualified every other use), so a component is read through
    its own shadow leaf. }
  IF (nt = 'Identifier') OR (nt = 'Designator') THEN
  BEGIN
    base_tracked := ValidateInitckDesignator(node, read_value, ctx, rec_tid);
    RETURN;
  END;
  IF read_value AND InitckEnabled(node) THEN
  BEGIN
    IF nt = 'FuncCall' THEN
    BEGIN
      { A user routine's actuals are validated below like any other reads;
        other builtins may consume storage through addresses. }
      nm := UpperStr(GetStr(node, 'name'));
      IF LookupRoutine(nm) = 0 THEN
        IF (nm <> 'ORD') AND (nm <> 'CHR') AND (nm <> 'ODD') AND
           (nm <> 'ABS') AND (nm <> 'UNSAFERAW') AND (nm <> 'UNSAFESUPER') AND
           (nm <> 'EOF') AND (nm <> 'EOLN') AND NOT InitckDeviceValueBuiltin(nm) THEN
          InitckBoundaryAt('call consumer', node);
    END
    ELSE IF (nt <> '') AND (nt <> 'IntLiteral') AND
      (nt <> 'RealLiteral') AND (nt <> 'BoolLiteral') AND
      (nt <> 'CharLiteral') AND (nt <> 'StringLiteral') AND
      (nt <> 'NilLiteral') AND (nt <> 'BinOp') AND (nt <> 'UnaryOp') AND
      (nt <> 'FuncCall') AND (nt <> 'AdrExpr') THEN
      InitckBoundaryAt('unsupported expression', node);
  END;
  IF (nt = 'ProcCallStmt') OR (nt = 'FuncCall') THEN
  BEGIN
    nm := UpperStr(GetStr(node, 'name'));
    ri := LookupRoutine(nm);
    args := GetObj(node, 'args');
    { PUT consumes the whole buffer (InitckGuardPut). }
    IF (ri = 0) AND (nm = 'PUT') AND (ArrSize(args) > 0) THEN
      IF InitckEnabled(ArrItem(args, 0)) AND (InitckFileElem(ArrItem(args, 0)) = 0) THEN
        InitckBoundaryAt('file buffer', ArrItem(args, 0));
    FOR i := 0 TO ArrSize(args) - 1 DO
    BEGIN
      arg_reads := TRUE;
      arg_ctx := INITCK_CTX_PLAIN;
      IF ri <> 0 THEN
      BEGIN
        IF i < routines[ri].nparams THEN
          IF routines[ri].param_is_var[i + 1] THEN
          BEGIN
            arg_reads := FALSE;
            { A tracked VAR/CONST formal of a transporting routine shares
              the actual's state (CodegenCallCommon); any other binding
              leaves the storage to untracked writes. }
            IF (NOT InitckTransports(ri)) OR
               (InitckShadowSize(routines[ri].param_tk[i + 1]) = 0) THEN
              arg_ctx := INITCK_CTX_EFFECT;
          END;
      END
      ELSE IF (nm = 'READ') OR (nm = 'READLN') THEN
      BEGIN
        arg_reads := FALSE;
        arg_ctx := INITCK_CTX_IO;
      END
      ELSE IF (nm = 'WRITE') OR (nm = 'WRITELN') THEN arg_ctx := INITCK_CTX_IO
      ELSE IF (nm = 'NEW') AND (i = 0) THEN arg_reads := FALSE
      ELSE IF (nm <> 'ORD') AND (nm <> 'CHR') AND (nm <> 'ODD') AND
              (nm <> 'ABS') AND (nm <> 'NEW') AND (nm <> 'DISPOSE') AND
              (nm <> 'UNSAFERAW') AND (nm <> 'UNSAFESUPER') AND
              NOT InitckDeviceValueBuiltin(nm) THEN
        arg_ctx := INITCK_CTX_EFFECT;
      { Binding an alias or naming an input destination is not a read of
        its old contents. Selection operands remain independent reads. }
      ValidateInitckReads(ArrItem(args, i), arg_reads, arg_ctx);
    END;
    RETURN;
  END;
  { cJSON array access also walks object children. Metadata has no AST
    node types and contributes no reads. Target selectors still consume
    indices, so recurse in read mode below a non-reading target root. Only
    ADR hands its operand (not a value read) to the alias/effect context;
    every other node's operands are plain value reads. }
  IF nt <> 'AdrExpr' THEN ctx := INITCK_CTX_PLAIN;
  FOR i := 0 TO ArrSize(node) - 1 DO
    ValidateInitckReads(ArrItem(node, i), nt <> 'AdrExpr', ctx);
END;

FUNCTION InitckNamesAdr(node: ADRMEM; uname: Str255): BOOLEAN;
{ Does any ADR in this subtree (nested routines included) name uname? A
  conservative, name-only over-approximation. }
VAR
  i: INTEGER32;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  IF NodeType(node) = 'AdrExpr' THEN
    found := UpperStr(GetStr(node, 'name')) = uname
  ELSE
    FOR i := 0 TO ArrSize(node) - 1 DO
      IF NOT found THEN found := InitckNamesAdr(ArrItem(node, i), uname);
  InitckNamesAdr := found;
END;

(*$INCLUDE:'cg_initck_proof.inc'*)

PROCEDURE PrepareInitckLocals(body: ADRMEM);
VAR
  i: INTEGER32;
  ready: BOOLEAN;
BEGIN
  initck_nproven := 0;
  initck_routine_body := body;
  initck_field_scan := FALSE;
  FOR i := CurScopeBase + 1 TO nsymbols DO
    IF symbols[i].init_state <> NIL THEN
      IF InitckLocalEscapes(body, symbols[i].name, symbols[i].tk, FALSE, FALSE, FALSE, FALSE) THEN
      BEGIN
        { An escaped VAR/CONST formal can be written through untracked
          effects (ADR, [C] or builtin calls) that never update the caller's
          state. Release the caller's slot as initialized rather than risk
          failing a correct caller: a documented coverage gap, never a false
          positive. Still in the prologue, before any user statement. }
        IF symbols[i].init_shared THEN
          IF InitckTrackedTk(symbols[i].tk) THEN
            LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), symbols[i].init_state)
          ELSE
            InitckTransferShadow(symbols[i].init_state, NIL, symbols[i].tk,
                                 LLVMConstInt(i1ty, 1, 0));
        symbols[i].init_state := NIL;
      END;
  IF NodeType(body) = 'Block' THEN
  BEGIN
    { The closing END is a function's fallthrough return read site. }
    IF InitckEnabled(body) AND (cur_func_name <> '') AND (cur_func_ret_state = NIL) THEN
      InitckBoundaryAt('function result', body);
    ValidateInitckReads(GetObj(body, 'body'), TRUE, INITCK_CTX_PLAIN);
  END
  ELSE ValidateInitckReads(body, TRUE, INITCK_CTX_PLAIN);
  IF NOT InitckProofBlocked(body) THEN
    FOR i := CurScopeBase + 1 TO nsymbols DO
      IF (symbols[i].init_state <> NIL) AND (NOT symbols[i].is_param) AND
         (NOT symbols[i].is_with_field) AND
         ((symbols[i].tk = TK_INTEGER) OR (symbols[i].tk = TK_BOOLEAN) OR
          (symbols[i].tk = TK_CHAR)) THEN
      BEGIN
        ready := FALSE;
        InitckProofStmt(body, i, ready);
      END;
END;

FUNCTION InitckTracked(symi: INTEGER32): BOOLEAN;
{ A direct, uncaptured slot of the current activation with shadow state.
  WITH's pushed scopes do not hide the routine's own slots. }
BEGIN
  InitckTracked := FALSE;
  IF symi > initck_scope_base THEN
    InitckTracked := symbols[symi].init_state <> NIL;
END;

FUNCTION InitckPointerTk(tk: INTEGER): BOOLEAN;
{ A plain host typed pointer `^T`, or a host SUPER ARRAY descriptor
  (data and upper): its whole value is one tracked leaf, whatever T is. A
  descriptor is published and copied whole, and its leaf is separate from
  the state of the elements it locates. ADS pointers are excluded. }
BEGIN
  InitckPointerTk := FALSE;
  IF TypeKind(tk) = TK_POINTER THEN
    InitckPointerTk := types[tk].ptr_space = PTR_SPACE_PLAIN;
END;

FUNCTION InitckTrackedTk(tk: INTEGER): BOOLEAN;
{ Exact semantic types only: TypeKind would also admit subranges. A raw
  address (ADRMEM, ADSMEM, CPTR) is a value leaf like a typed pointer's,
  but locates nothing INITCK tracks: only the address value itself is
  checked. }
BEGIN
  InitckTrackedTk := (tk = TK_INTEGER) OR (tk = TK_BOOLEAN) OR (tk = TK_CHAR) OR
                     (tk = TK_ADRMEM) OR InitckPointerTk(tk);
END;

FUNCTION InitckTransports(ri: INTEGER32): BOOLEAN;
{ Host Pascal-to-Pascal calls carry argument and result state through the
  runtime's thread-local side channel; calling conventions never change.
  [C] routines and every DEVICE compiland are outside it. }
BEGIN
  InitckTransports := FALSE;
  IF ri <> 0 THEN
    InitckTransports := (NOT routines[ri].is_c) AND (NOT is_device_compiland);
END;

FUNCTION InitckResultTracked(ri: INTEGER32): BOOLEAN;
BEGIN
  InitckResultTracked := FALSE;
  IF InitckTransports(ri) THEN
    IF RoutineIsFunc(ri) THEN
      InitckResultTracked := InitckTrackedTk(routines[ri].ret_tk);
END;

FUNCTION InitckArgSlot(i: INTEGER32): ADRMEM;
{ Address of formal i's (1-based) slot in pas_initck_args (runtime/initck.c). }
VAR
  g, arr_ty, idx: ADRMEM;
BEGIN
  arr_ty := LLVMArrayType(i8ptrty, MAX_PARAMS);
  g := LLVMGetNamedGlobal(modl, MakeCStr('pas_initck_args'));
  IF g = NIL THEN
  BEGIN
    g := LLVMAddGlobal(modl, arr_ty, MakeCStr('pas_initck_args'));
    LLVMSetThreadLocal(g, 1);
  END;
  idx := AllocPtrArray(2);
  SetPtrArrayElem(idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(idx, 1, LLVMConstInt(i32ty, i - 1, 0));
  InitckArgSlot := LLVMBuildGEP2(builder, arr_ty, g, idx, 2, MakeCStr(''));
END;

FUNCTION InitckTls(gname: Str255; ty: ADRMEM): ADRMEM;
{ A thread-local side-channel variable defined in runtime/initck.c. }
VAR
  g: ADRMEM;
BEGIN
  g := LLVMGetNamedGlobal(modl, MakeCStr(gname));
  IF g = NIL THEN
  BEGIN
    g := LLVMAddGlobal(modl, ty, MakeCStr(gname));
    LLVMSetThreadLocal(g, 1);
  END;
  InitckTls := g;
END;

FUNCTION InitckRetFlag: ADRMEM;
{ pas_initck_ret (runtime/initck.c): the last returned tracked result's state. }
BEGIN
  InitckRetFlag := InitckTls('pas_initck_ret', i1ty);
END;

PROCEDURE InitckAcceptChannel(fn: ADRMEM);
{ Prologue of a transporting routine with a tracked formal or result, before
  any receive or call. The published slots are this routine's only when its
  caller tagged it (pas_initck_callee): a Pascal routine that C calls back
  while C runs a plain EXTERN some Pascal caller published for sees another
  tag and treats its formals as initialized, as for any uninstrumented
  caller. When tagged, acknowledge through the caller's flag (if any), which
  tells it the callee was instrumented. Clears the tag and the flag pointer.
  No branch: an untagged or flagless call stores into a private dummy. }
VAR
  tag_g, ack_g, tag, ackp, mine, dummy, target: ADRMEM;
BEGIN
  tag_g := InitckTls('pas_initck_callee', i8ptrty);
  ack_g := InitckTls('pas_initck_ack', i8ptrty);
  tag := LLVMBuildLoad2(builder, i8ptrty, tag_g, MakeCStr('initck.tag'));
  ackp := LLVMBuildLoad2(builder, i8ptrty, ack_g, MakeCStr('initck.ackp'));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), tag_g);
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), ack_g);
  mine := LLVMBuildICmp(builder, LLVMIntEQ, tag,
                        LLVMBuildBitCast(builder, fn, i8ptrty, MakeCStr('')),
                        MakeCStr('initck.mine'));
  dummy := EntryAlloca(i1ty, 'initck.noack');
  target := LLVMBuildSelect(builder,
    LLVMBuildAnd(builder, mine,
      LLVMBuildICmp(builder, LLVMIntNE, ackp, LLVMConstNull(i8ptrty), MakeCStr('')),
      MakeCStr('')),
    ackp, LLVMBuildBitCast(builder, dummy, i8ptrty, MakeCStr('')), MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), target);
  initck_accept := mine;
END;

FUNCTION InitckDescriptorData(addr: ADRMEM; tid: INTEGER): ADRMEM;
{ The element data address of the host SUPER ARRAY descriptor stored at
  addr, loaded now (before a call that may replace it). }
BEGIN
  InitckDescriptorData := LLVMBuildExtractValue(builder,
    LLVMBuildLoad2(builder, LLVMTypeForTk(tid), addr, MakeCStr('')), 0, MakeCStr('initck.desc.data'));
END;

PROCEDURE InitckReleaseUnacked(acked, shadow: ADRMEM; tid: INTEGER);
{ After a call to a plain EXTERN that did not acknowledge the side channel
  (C, not instrumented Pascal): it may have written the storage bound to a
  VAR/CONST formal, so those leaves become initialized. Acknowledged calls
  keep the state the callee's own writes published. }
VAR
  tys, args, discard: ADRMEM;
BEGIN
  tys := AllocPtrArray(3);
  args := AllocPtrArray(3);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, shadow, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(tys, 1, i64ty);
  SetPtrArrayElem(args, 1, LLVMConstInt(i64ty, InitckShadowSize(tid), 0));
  SetPtrArrayElem(tys, 2, i32ty);
  SetPtrArrayElem(args, 2, LLVMBuildZExt(builder, acked, i32ty, MakeCStr('')));
  discard := InitckCall('pas_initck_release_unacked', voidty, tys, args, 3);
END;

FUNCTION ReceiveInitckArg(i: INTEGER32; name: Str255; shared: BOOLEAN): ADRMEM;
{ Callee prologue for tracked formal i. A value formal copies the caller's
  published state; a shared (VAR/CONST) formal instead uses the published
  pointer itself, so its reads check and its writes update the caller's
  storage state. With nothing published (an uninstrumented caller, or an
  actual outside the tracked slice) the formal gets a private slot that is
  initialized. Clears the slot so it can never be read stale. Must precede
  any call. }
VAR
  own, slot, p, q, isnull: ADRMEM;
  state_name: Str255;
BEGIN
  state_name := 'initck.';
  CONCAT(state_name, name);
  own := EntryAlloca(i1ty, state_name);
  slot := InitckArgSlot(i);
  p := LLVMBuildLoad2(builder, i8ptrty, slot, MakeCStr('initck.arg'));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), slot);
  IF initck_accept <> NIL THEN
    p := LLVMBuildSelect(builder, initck_accept, p, LLVMConstNull(i8ptrty), MakeCStr('initck.argok'));
  LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), own);
  isnull := LLVMBuildICmp(builder, LLVMIntEQ, p, LLVMConstNull(i8ptrty), MakeCStr(''));
  IF shared THEN CONCAT(state_name, '.ref') ELSE state_name := '';
  q := LLVMBuildSelect(builder, isnull, own, p, MakeCStr(state_name));
  IF shared THEN ReceiveInitckArg := q
  ELSE
  BEGIN
    LLVMBuildStore(builder, LLVMBuildLoad2(builder, i1ty, q, MakeCStr('')), own);
    ReceiveInitckArg := own;
  END;
END;

FUNCTION ReceiveInitckAggregate(i: INTEGER32; name: Str255; tid: INTEGER;
                                shared: BOOLEAN): ADRMEM;
{ Callee prologue for a tracked aggregate formal. A value formal's own
  shadow takes the snapshot the Pascal caller published for actual i; a
  VAR/CONST formal uses the caller's published shadow itself (whole storage,
  a sub-aggregate, ...), so its writes update the caller's leaves. With
  nothing published, the formal gets private, wholly initialized leaves.
  Clears the slot. Must precede any call, like ReceiveInitckArg. }
VAR
  own, slot, p, tys, args, discard: ADRMEM;
  state_name: Str255;
BEGIN
  state_name := 'initck.';
  CONCAT(state_name, name);
  own := EntryAlloca(InitckShadowTy(tid), state_name);
  slot := InitckArgSlot(i);
  p := LLVMBuildLoad2(builder, i8ptrty, slot, MakeCStr('initck.arg'));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), slot);
  IF initck_accept <> NIL THEN
    p := LLVMBuildSelect(builder, initck_accept, p, LLVMConstNull(i8ptrty), MakeCStr('initck.argok'));
  IF shared THEN
  BEGIN
    InitckTransferShadow(own, NIL, tid, LLVMConstInt(i1ty, 1, 0));
    CONCAT(state_name, '.ref');
    ReceiveInitckAggregate := LLVMBuildSelect(builder,
      LLVMBuildICmp(builder, LLVMIntEQ, p, LLVMConstNull(i8ptrty), MakeCStr('')),
      own, p, MakeCStr(state_name));
    RETURN;
  END;
  tys := AllocPtrArray(3);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(tys, 1, i8ptrty);
  SetPtrArrayElem(tys, 2, i64ty);
  args := AllocPtrArray(3);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, own, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(args, 1, p);
  SetPtrArrayElem(args, 2, LLVMConstInt(i64ty, InitckShadowSize(tid), 0));
  discard := InitckCall('pas_initck_receive', voidty, tys, args, 3);
  ReceiveInitckAggregate := own;
END;

PROCEDURE NoteInitckState(state: ADRMEM);
{ AND a produced i1 state into the active value accumulator, if any. }
BEGIN
  IF initck_taint <> NIL THEN
    LLVMBuildStore(builder, LLVMBuildAnd(builder, state,
      LLVMBuildLoad2(builder, i1ty, initck_taint, MakeCStr('')), MakeCStr('')), initck_taint);
END;

PROCEDURE GuardInitckCond(state: ADRMEM; what, name: Str255; node: ADRMEM);
{ Branch on metadata only; the failure block never touches program bytes. }
VAR
  bad_bb, ok_bb, ps, fnty, fn, args, discard: ADRMEM;
  nargs: INTEGER32;
BEGIN
  bad_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.bad'));
  ok_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.ok'));
  LLVMBuildCondBr(builder, state, ok_bb, bad_bb);
  LLVMPositionBuilderAtEnd(builder, bad_bb);
  { Locals keep the original pas_initck_error entry; other kinds name
    themselves through pas_initck_fail. }
  IF what = 'local' THEN nargs := 3 ELSE nargs := 4;
  ps := AllocPtrArray(nargs);
  args := AllocPtrArray(nargs);
  IF nargs = 4 THEN
  BEGIN
    SetPtrArrayElem(ps, 0, i8ptrty);
    SetPtrArrayElem(args, 0, LLVMBuildGlobalStringPtr(builder,
      MakeCStr(what), MakeCStr('initck.what')));
  END;
  SetPtrArrayElem(ps, nargs - 3, i8ptrty);
  SetPtrArrayElem(ps, nargs - 2, i32ty);
  SetPtrArrayElem(ps, nargs - 1, i32ty);
  fnty := LLVMFunctionType(voidty, ps, nargs, 0);
  IF nargs = 4 THEN
  BEGIN
    fn := LLVMGetNamedFunction(modl, MakeCStr('pas_initck_fail'));
    IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_initck_fail'), fnty);
  END
  ELSE
  BEGIN
    fn := LLVMGetNamedFunction(modl, MakeCStr('pas_initck_error'));
    IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr('pas_initck_error'), fnty);
  END;
  SetPtrArrayElem(args, nargs - 3, LLVMBuildGlobalStringPtr(builder,
    MakeCStr(name), MakeCStr('initck.name')));
  { Legacy ASTs may retain read flags without source coordinates. GetInt
    returns zero for missing fields; the runtime then reports only the name. }
  SetPtrArrayElem(args, nargs - 2, LLVMConstInt(i32ty,
    GetInt(GetObj(node, 'read_location'), 'line'), 0));
  SetPtrArrayElem(args, nargs - 1, LLVMConstInt(i32ty,
    GetInt(GetObj(node, 'read_location'), 'column'), 0));
  discard := LLVMBuildCall2(builder, fnty, fn, args, nargs, MakeCStr(''));
  discard := LLVMBuildUnreachable(builder);
  LLVMPositionBuilderAtEnd(builder, ok_bb);
END;

PROCEDURE GuardInitckState(state_ptr: ADRMEM; what, name: Str255; node: ADRMEM);
BEGIN
  GuardInitckCond(LLVMBuildLoad2(builder, i1ty, state_ptr, MakeCStr('initck.ready')),
                  what, name, node);
END;

FUNCTION InitckCall(fname: Str255; ret_ty, tys, args: ADRMEM; n: INTEGER32): ADRMEM;
{ Call a runtime/initck.c helper, declaring it on first use. }
VAR
  fnty, fn: ADRMEM;
BEGIN
  fnty := LLVMFunctionType(ret_ty, tys, n, 0);
  fn := LLVMGetNamedFunction(modl, MakeCStr(fname));
  IF fn = NIL THEN fn := LLVMAddFunction(modl, MakeCStr(fname), fnty);
  InitckCall := LLVMBuildCall2(builder, fnty, fn, args, n, MakeCStr(''));
END;

FUNCTION InitckHasVariant(tid: INTEGER): BOOLEAN;
{ Does a shadowed type contain a record variant part anywhere? }
VAR
  fi: INTEGER;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  IF TypeKind(tid) = TK_ARRAY THEN found := InitckHasVariant(types[tid].elem_tid)
  ELSE IF TypeKind(tid) = TK_RECORD THEN
    FOR fi := 1 TO nfields DO
      IF fields[fi].rec_tid = tid THEN
      BEGIN
        IF fields[fi].arm <> 0 THEN found := TRUE;
        IF InitckHasVariant(fields[fi].field_tid) THEN found := TRUE;
      END;
  InitckHasVariant := found;
END;

FUNCTION InitckFieldShadow(shadow: ADRMEM; fi: INTEGER): ADRMEM;
VAR
  gep_idx: ADRMEM;
BEGIN
  gep_idx := AllocPtrArray(1);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, InitckFieldShadowOffset(fi), 0));
  InitckFieldShadow := LLVMBuildGEP2(builder, i1ty, shadow, gep_idx, 1, MakeCStr('initck.field'));
END;

FUNCTION InitckVariantAllState(shadow: ADRMEM; tid: INTEGER): ADRMEM;
{ A whole-value read of a type containing variant parts transfers its
  logical components: every fixed field (the tag included) and, for each
  record, ONE complete alternative (any one: this is not active-variant or
  tag checking; an alternative with no fields is always complete). Inactive
  alternatives present in the allocation are not consumed. An array checks
  each element in an emitted loop. }
VAR
  acc, any_arm, arm_ok, idx_slot, acc_slot, gep_idx, i_val, elem: ADRMEM;
  cond_bb, body_bb, done_bb: ADRMEM;
  fi, arm, narms: INTEGER;
  seen: BOOLEAN;
BEGIN
  IF TypeKind(tid) = TK_RECORD THEN
  BEGIN
    acc := LLVMConstInt(i1ty, 1, 0);
    narms := 0;
    FOR fi := 1 TO nfields DO
      IF fields[fi].rec_tid = tid THEN
      BEGIN
        IF fields[fi].arm = 0 THEN
          acc := LLVMBuildAnd(builder, acc,
            InitckAllState(InitckFieldShadow(shadow, fi), fields[fi].field_tid), MakeCStr(''))
        ELSE IF fields[fi].arm > narms THEN narms := fields[fi].arm;
      END;
    IF (narms > 0) AND NOT types[tid].variant_empty THEN
    BEGIN
      any_arm := LLVMConstInt(i1ty, 0, 0);
      FOR arm := 1 TO narms DO
      BEGIN
        arm_ok := LLVMConstInt(i1ty, 1, 0);
        seen := FALSE;
        FOR fi := 1 TO nfields DO
          IF (fields[fi].rec_tid = tid) AND (fields[fi].arm = arm) THEN
          BEGIN
            seen := TRUE;
            arm_ok := LLVMBuildAnd(builder, arm_ok,
              InitckAllState(InitckFieldShadow(shadow, fi), fields[fi].field_tid), MakeCStr(''));
          END;
        IF seen THEN any_arm := LLVMBuildOr(builder, any_arm, arm_ok, MakeCStr(''));
      END;
      acc := LLVMBuildAnd(builder, acc, any_arm, MakeCStr(''));
    END;
    InitckVariantAllState := acc;
  END
  ELSE
  BEGIN
    acc_slot := EntryAlloca(i1ty, 'initck.all');
    idx_slot := EntryAlloca(i64ty, 'initck.i');
    LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), acc_slot);
    LLVMBuildStore(builder, LLVMConstInt(i64ty, 0, 0), idx_slot);
    cond_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.all.cond'));
    body_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.all.body'));
    done_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.all.done'));
    LLVMBuildBr(builder, cond_bb);
    LLVMPositionBuilderAtEnd(builder, cond_bb);
    i_val := LLVMBuildLoad2(builder, i64ty, idx_slot, MakeCStr(''));
    LLVMBuildCondBr(builder, LLVMBuildICmp(builder, LLVMIntSLT, i_val,
      LLVMConstInt(i64ty, types[tid].hi - types[tid].lo + 1, 0), MakeCStr('')), body_bb, done_bb);
    LLVMPositionBuilderAtEnd(builder, body_bb);
    gep_idx := AllocPtrArray(2);
    SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
    SetPtrArrayElem(gep_idx, 1, i_val);
    elem := LLVMBuildGEP2(builder, InitckShadowTy(tid), shadow, gep_idx, 2, MakeCStr('initck.elem'));
    acc := InitckAllState(elem, types[tid].elem_tid);
    LLVMBuildStore(builder, LLVMBuildAnd(builder, acc,
      LLVMBuildLoad2(builder, i1ty, acc_slot, MakeCStr('')), MakeCStr('')), acc_slot);
    LLVMBuildStore(builder, LLVMBuildAdd(builder, i_val, LLVMConstInt(i64ty, 1, 0), MakeCStr('')), idx_slot);
    LLVMBuildBr(builder, cond_bb);
    LLVMPositionBuilderAtEnd(builder, done_bb);
    InitckVariantAllState := LLVMBuildLoad2(builder, i1ty, acc_slot, MakeCStr(''));
  END;
END;

FUNCTION InitckAllState(shadow: ADRMEM; tid: INTEGER): ADRMEM;
{ i1: is every logical component of the shadowed value initialized? }
VAR
  tys, args, r: ADRMEM;
BEGIN
  IF InitckTrackedTk(tid) THEN
    InitckAllState := LLVMBuildLoad2(builder, i1ty, shadow, MakeCStr('initck.ready'))
  ELSE IF InitckHasVariant(tid) THEN
    InitckAllState := InitckVariantAllState(shadow, tid)
  ELSE
  BEGIN
    tys := AllocPtrArray(2);
    SetPtrArrayElem(tys, 0, i8ptrty);
    SetPtrArrayElem(tys, 1, i64ty);
    args := AllocPtrArray(2);
    SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, shadow, i8ptrty, MakeCStr('')));
    SetPtrArrayElem(args, 1, LLVMConstInt(i64ty, InitckShadowSize(tid), 0));
    r := InitckCall('pas_initck_all', i32ty, tys, args, 2);
    InitckAllState := LLVMBuildICmp(builder, LLVMIntNE, r, LLVMConstInt(i32ty, 0, 0),
                                    MakeCStr('initck.ready'));
  END;
END;

PROCEDURE InitckTransferShadow(dst, src: ADRMEM; tid: INTEGER; state: ADRMEM);
{ After an aggregate copy's data store: dst takes src's leaf states (a NIL
  src is untracked storage, initialized by assumption), all unset when the
  transfer itself consumed unset state. }
VAR
  tys, args, discard: ADRMEM;
  n: INTEGER32;
BEGIN
  IF src = NIL THEN n := 3 ELSE n := 4;
  tys := AllocPtrArray(n);
  args := AllocPtrArray(n);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, dst, i8ptrty, MakeCStr('')));
  IF src <> NIL THEN
  BEGIN
    SetPtrArrayElem(tys, 1, i8ptrty);
    SetPtrArrayElem(args, 1, LLVMBuildBitCast(builder, src, i8ptrty, MakeCStr('')));
  END;
  SetPtrArrayElem(tys, n - 2, i64ty);
  SetPtrArrayElem(args, n - 2, LLVMConstInt(i64ty, InitckShadowSize(tid), 0));
  SetPtrArrayElem(tys, n - 1, i32ty);
  SetPtrArrayElem(args, n - 1, LLVMBuildZExt(builder, state, i32ty, MakeCStr('')));
  IF src = NIL THEN discard := InitckCall('pas_initck_fill', voidty, tys, args, n)
  ELSE discard := InitckCall('pas_initck_copy', voidty, tys, args, n);
END;

PROCEDURE GuardInitckWhole(node, shadow: ADRMEM; tid: INTEGER; name: Str255);
{ A whole-value read of tracked aggregate storage: when enabled, every
  transferred leaf must be initialized before the native load (the strict
  checked-copy rule); unchecked, it joins the value accumulator, unless it
  is the source of the aggregate copy being lowered, which transfers leaf
  states exactly instead. }
BEGIN
  IF InitckEnabled(node) THEN
    GuardInitckCond(InitckAllState(shadow, tid), 'part of', name, node)
  ELSE IF (initck_taint <> NIL) AND (node <> initck_copy_source) THEN
    NoteInitckState(InitckAllState(shadow, tid));
END;

PROCEDURE InitckPublishResult(node: ADRMEM);
{ At each normal return of a function: an enabled return (RETURN token or
  the body's closing END) reads the result it publishes, so check it; then
  hand its state to a transporting caller. Unwritten results keep their
  zero/default bytes either way: those bytes are not an initialization. }
VAR
  state: ADRMEM;
BEGIN
  IF cur_func_name <> '' THEN
  BEGIN
    IF cur_func_ret_state = NIL THEN
    BEGIN
      IF InitckEnabled(node) THEN
        InitckBoundaryAt('function result', node);
    END
    ELSE
    BEGIN
      IF InitckEnabled(node) THEN
        GuardInitckState(cur_func_ret_state, 'result of', cur_func_name, node);
      IF InitckTransports(LookupRoutine(cur_func_name)) THEN
      BEGIN
        state := LLVMBuildLoad2(builder, i1ty, cur_func_ret_state, MakeCStr('initck.result'));
        LLVMBuildStore(builder, state, InitckRetFlag);
      END;
    END;
  END;
END;

FUNCTION InitckTaintSources(node: ADRMEM): BOOLEAN;
{ TRUE when evaluating node may perform an UNCHECKED read of tracked storage
  or call a function whose result state is transported, i.e. when the
  produced value's state is not known to be initialized. A checked read
  either fails or proves its slot initialized. }
VAR
  nt: Str255;
  i, symi: INTEGER32;
  found, deref: BOOLEAN;
BEGIN
  nt := NodeType(node);
  found := FALSE;
  IF (nt = 'Identifier') OR (nt = 'Designator') THEN
    IF ArrSize(GetObj(node, 'selectors')) = 0 THEN
    BEGIN
      symi := LookupSym(GetStr(node, 'name'));
      IF InitckTracked(symi) THEN
      BEGIN
        IF NOT InitckEnabled(node) THEN found := TRUE;
      END
      ELSE IF symi = 0 THEN { a niladic call }
        IF InitckResultTracked(LookupRoutine(GetStr(node, 'name'))) THEN found := TRUE;
    END;
  IF nt = 'Designator' THEN
    IF ArrSize(GetObj(node, 'selectors')) <> 0 THEN
    BEGIN
      { Selected storage may be tracked through its root or, past a DEREF,
        on the heap; an unchecked DEREF reads its pointer's state too. }
      deref := FALSE;
      FOR i := 0 TO ArrSize(GetObj(node, 'selectors')) - 1 DO
        IF GetStr(ArrItem(GetObj(node, 'selectors'), i), 'kind') = 'DEREF' THEN
        BEGIN
          deref := TRUE;
          IF NOT InitckEnabled(ArrItem(GetObj(node, 'selectors'), i)) THEN found := TRUE;
        END;
      IF deref OR InitckTracked(LookupSym(GetStr(node, 'name'))) THEN
        IF NOT InitckEnabled(node) THEN found := TRUE;
    END;
  { A Pascal function's result arrives with the state its return published. }
  IF nt = 'FuncCall' THEN
    IF InitckResultTracked(LookupRoutine(GetStr(node, 'name'))) THEN found := TRUE;
  FOR i := 0 TO ArrSize(node) - 1 DO
    IF InitckTaintSources(ArrItem(node, i)) THEN found := TRUE;
  InitckTaintSources := found;
END;

FUNCTION BeginInitckValue(expr: ADRMEM): ADRMEM;
{ Start collecting the state of the value expr produces; returns the outer
  accumulator for EndInitckValue. No machinery when no unchecked tracked
  read can occur: the value is then initialized by construction. }
BEGIN
  BeginInitckValue := initck_taint;
  initck_taint := NIL;
  IF InitckTaintSources(expr) THEN
  BEGIN
    initck_taint := EntryAlloca(i1ty, 'initck.taint');
    LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), initck_taint);
  END;
END;

FUNCTION EndInitckValue(saved: ADRMEM): ADRMEM;
{ The collected i1 state: TRUE unless an evaluated unchecked read consumed
  an unset tracked slot. Restores the outer accumulator. }
BEGIN
  IF initck_taint = NIL THEN EndInitckValue := LLVMConstInt(i1ty, 1, 0)
  ELSE EndInitckValue := LLVMBuildLoad2(builder, i1ty, initck_taint, MakeCStr('initck.value'));
  initck_taint := saved;
END;

PROCEDURE GuardInitckRead(node: ADRMEM; symi: INTEGER32);
VAR
  state: ADRMEM;
  proof_i: INTEGER32;
BEGIN
  IF InitckTracked(symi) THEN
    IF NOT InitckTrackedTk(symbols[symi].tk) THEN
    BEGIN
      GuardInitckWhole(node, symbols[symi].init_state, symbols[symi].tk, symbols[symi].name);
      RETURN;
    END;
  { Unchecked reads propagate rather than check: only evaluated operands
    reach here, so skipped AND THEN/OR ELSE operands contribute nothing. }
  IF (initck_taint <> NIL) AND (NOT InitckEnabled(node)) THEN
    IF InitckTracked(symi) THEN
    BEGIN
      state := LLVMBuildLoad2(builder, i1ty, symbols[symi].init_state, MakeCStr('initck.src'));
      NoteInitckState(state);
    END;
  IF NOT InitckEnabled(node) THEN RETURN;
  IF (symi <= initck_scope_base) OR (symbols[symi].init_state = NIL) THEN
    InitckBoundaryAt(InitckSymCategory(symi), node);
  FOR proof_i := 1 TO initck_nproven DO
    IF (initck_proven_nodes[proof_i] = node) AND
       (initck_proven_syms[proof_i] = symi) THEN RETURN;
  IF symbols[symi].is_param THEN
    GuardInitckState(symbols[symi].init_state, 'parameter', symbols[symi].name, node)
  ELSE IF symbols[symi].is_with_field THEN
    GuardInitckState(symbols[symi].init_state, 'field', symbols[symi].name, node)
  ELSE
    GuardInitckState(symbols[symi].init_state, 'local', symbols[symi].name, node);
END;

PROCEDURE GuardInitckComponent(node, shadow: ADRMEM; tid: INTEGER);
{ A selected component's read: a scalar leaf is checked against its own
  shadow leaf when enabled at node, else its state joins the active value
  accumulator; a selected sub-aggregate is a whole-value read. The
  designator's index operands and bounds checks have already run. }
BEGIN
  IF NOT InitckTrackedTk(tid) THEN
    GuardInitckWhole(node, shadow, tid, InitckDesigText(node))
  ELSE IF InitckEnabled(node) THEN
    GuardInitckState(shadow, 'component', InitckDesigText(node), node)
  ELSE IF initck_taint <> NIL THEN
    NoteInitckState(LLVMBuildLoad2(builder, i1ty, shadow, MakeCStr('initck.src')));
END;

FUNCTION InitckHeapFallback(leaves: INTEGER32): ADRMEM;
{ This lookup site's own run of leaves for an untracked referent: aliases
  bound at different sites never share state bytes, and none outlives the
  frame that bound it. }
VAR
  n: INTEGER32;
BEGIN
  n := leaves;
  IF n < 1 THEN n := 1;
  InitckHeapFallback := LLVMBuildBitCast(builder,
    EntryAlloca(LLVMArrayType(i8ty, n), 'initck.untracked'), i8ptrty, MakeCStr(''));
END;

FUNCTION InitckHeapShadow(data: ADRMEM; ptr_tid: INTEGER): ADRMEM;
{ The state of the referent at data (pas_initck_heap_at): the leaves NEW
  registered, or this site's initialized fallback for an untracked or
  released one. }
VAR
  tys, args: ADRMEM;
  leaves: INTEGER32;
BEGIN
  leaves := InitckShadowSize(types[ptr_tid].elem_tid);
  tys := AllocPtrArray(3);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(tys, 1, i64ty);
  SetPtrArrayElem(tys, 2, i8ptrty);
  args := AllocPtrArray(3);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, data, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(args, 1, LLVMConstInt(i64ty, leaves, 0));
  SetPtrArrayElem(args, 2, InitckHeapFallback(leaves));
  InitckHeapShadow := InitckCall('pas_initck_heap_at', i8ptrty, tys, args, 3);
END;

PROCEDURE InitckHeapNew(data: ADRMEM; ptr_tid: INTEGER);
{ After a successful allocation and before the pointer is published: every
  leaf of the new referent starts unset (pas_initck_heap_new aborts, before
  publication, if it cannot record that). }
VAR
  tys, args, discard: ADRMEM;
BEGIN
  tys := AllocPtrArray(2);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(tys, 1, i64ty);
  args := AllocPtrArray(2);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, data, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(args, 1, LLVMConstInt(i64ty, InitckShadowSize(types[ptr_tid].elem_tid), 0));
  discard := InitckCall('pas_initck_heap_new', voidty, tys, args, 2);
END;

FUNCTION InitckSuperLeaves(high: ADRMEM; arr_tid: INTEGER): ADRMEM;
{ i64 leaf count of a SUPER ARRAY allocation with upper bound high: NEW and
  the import check keep upper >= lower and count * stride within the
  address space, and a tracked element has at most one leaf per byte. }
VAR
  count: ADRMEM;
BEGIN
  count := LLVMBuildAdd(builder, LLVMBuildSub(builder, high,
    LLVMConstInt(i64ty, types[arr_tid].lo, 1), MakeCStr('')),
    LLVMConstInt(i64ty, 1, 0), MakeCStr(''));
  InitckSuperLeaves := LLVMBuildMul(builder, count,
    LLVMConstInt(i64ty, InitckShadowSize(types[arr_tid].elem_tid), 0), MakeCStr('initck.leaves'));
END;

PROCEDURE InitckSuperNew(data, high: ADRMEM; arr_tid: INTEGER);
{ NEW of a SUPER ARRAY: after pas_super_new succeeded and before the
  descriptor is published, every leaf of every element starts unset. }
VAR
  tys, args, discard: ADRMEM;
BEGIN
  tys := AllocPtrArray(2);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(tys, 1, i64ty);
  args := AllocPtrArray(2);
  SetPtrArrayElem(args, 0, data);
  SetPtrArrayElem(args, 1, InitckSuperLeaves(high, arr_tid));
  discard := InitckCall('pas_initck_heap_new', voidty, tys, args, 2);
END;

FUNCTION InitckSuperElement(data, total, offset: ADRMEM; arr_tid: INTEGER): ADRMEM;
{ The state of element `offset` (0-based, i64) of a SUPER ARRAY allocation
  of total leaves (pas_initck_heap_part_at): out-of-range parts, as an
  INDEXCK- subscript may select, are this site's untracked fallback, never
  state beyond the allocation. }
VAR
  tys, args: ADRMEM;
  leaves: INTEGER32;
BEGIN
  leaves := InitckShadowSize(types[arr_tid].elem_tid);
  tys := AllocPtrArray(5);
  SetPtrArrayElem(tys, 0, i8ptrty);
  SetPtrArrayElem(tys, 1, i64ty);
  SetPtrArrayElem(tys, 2, i64ty);
  SetPtrArrayElem(tys, 3, i64ty);
  SetPtrArrayElem(tys, 4, i8ptrty);
  args := AllocPtrArray(5);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, data, i8ptrty, MakeCStr('')));
  SetPtrArrayElem(args, 1, total);
  SetPtrArrayElem(args, 2, LLVMBuildMul(builder, offset,
    LLVMConstInt(i64ty, leaves, 0), MakeCStr('')));
  SetPtrArrayElem(args, 3, LLVMConstInt(i64ty, leaves, 0));
  SetPtrArrayElem(args, 4, InitckHeapFallback(leaves));
  InitckSuperElement := InitckCall('pas_initck_heap_part_at', i8ptrty, tys, args, 5);
END;

PROCEDURE InitckHeapCall1(fname: Str255; data: ADRMEM);
VAR
  tys, args, discard: ADRMEM;
BEGIN
  tys := AllocPtrArray(1);
  SetPtrArrayElem(tys, 0, i8ptrty);
  args := AllocPtrArray(1);
  SetPtrArrayElem(args, 0, LLVMBuildBitCast(builder, data, i8ptrty, MakeCStr('')));
  discard := InitckCall(fname, voidty, tys, args, 1);
END;

PROCEDURE InitckHeapRelease(data: ADRMEM);
{ The referent at data reaches an unmodeled alias or effect: from now on
  it reads as untracked, initialized storage (pas_initck_heap_release). }
BEGIN
  InitckHeapCall1('pas_initck_heap_release', data);
END;

PROCEDURE InitckApplyRelease(p: ADRMEM; tid: INTEGER);
{ tid 0: release the heap referent at data address p; otherwise every leaf
  of the tid-typed state at p becomes initialized. }
BEGIN
  IF tid = 0 THEN InitckHeapRelease(p)
  ELSE IF InitckTrackedTk(tid) THEN
    LLVMBuildStore(builder, LLVMConstInt(i1ty, 1, 0), p)
  ELSE
    InitckTransferShadow(p, NIL, tid, LLVMConstInt(i1ty, 1, 0));
END;

PROCEDURE InitckReleaseAtCall(p: ADRMEM; tid: INTEGER);
{ An unmodeled effect on storage (a [C] write through a VAR binding, a
  referent or ADR address handed over) takes place at the call, after every
  actual is evaluated: a later actual still reads the old state. Outside a
  call's actuals it happens now. }
BEGIN
  IF initck_call_depth > 0 THEN InitckQueueRelease(p, tid)
  ELSE InitckApplyRelease(p, tid);
END;

PROCEDURE InitckGuardPending(base: INTEGER32; skip_bb, ran_bb: ADRMEM);
{ At the merge block of AND THEN/OR ELSE, whose right operand queued the
  effects above base: each now applies only when that operand ran (FALSE
  from skip_bb, its own guard from ran_bb, the operand's last block). The
  guard is a phi, so it dominates the call that applies it. So is the
  effect's address: one the operand computed (a data address, a selected
  state) is not defined on the skipped edge, which passes NULL instead;
  the guard is FALSE there, so the NULL is never used. }
VAR
  i: INTEGER32;
  e: PInitckPending;
  vals, blocks, phi: ADRMEM;
BEGIN
  blocks := AllocPtrArray(2);
  SetPtrArrayElem(blocks, 0, skip_bb);
  SetPtrArrayElem(blocks, 1, ran_bb);
  FOR i := base + 1 TO initck_npending DO
  BEGIN
    e := InitckPendingAt(i);
    phi := LLVMBuildPhi(builder, i1ty, MakeCStr('initck.ran'));
    vals := AllocPtrArray(2);
    SetPtrArrayElem(vals, 0, LLVMConstInt(i1ty, 0, 0));
    IF e^.guard = NIL THEN SetPtrArrayElem(vals, 1, LLVMConstInt(i1ty, 1, 0))
    ELSE SetPtrArrayElem(vals, 1, e^.guard);
    LLVMAddIncoming(phi, vals, blocks, 2);
    e^.guard := phi;
    phi := LLVMBuildPhi(builder, i8ptrty, MakeCStr('initck.at'));
    vals := AllocPtrArray(2);
    SetPtrArrayElem(vals, 0, LLVMConstNull(i8ptrty));
    SetPtrArrayElem(vals, 1, e^.p);
    LLVMAddIncoming(phi, vals, blocks, 2);
    e^.p := phi;
  END;
END;

PROCEDURE InitckFlushReleases(base: INTEGER32);
{ Just before a call: apply the effects its actuals queued above base, a
  guarded one only on the path where its operand ran. An unguarded address
  (an entry alloca, or the value of an actual) dominates the call; a
  guarded one is InitckGuardPending's phi, which does too. }
VAR
  e: PInitckPending;
  then_bb, after_bb: ADRMEM;
BEGIN
  WHILE initck_npending > base DO
  BEGIN
    e := InitckPendingAt(initck_npending);
    IF e^.guard = NIL THEN
      InitckApplyRelease(e^.p, e^.tid)
    ELSE
    BEGIN
      then_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.release'));
      after_bb := LLVMAppendBasicBlockInContext(ctx, cur_fn, MakeCStr('initck.released'));
      LLVMBuildCondBr(builder, e^.guard, then_bb, after_bb);
      LLVMPositionBuilderAtEnd(builder, then_bb);
      InitckApplyRelease(e^.p, e^.tid);
      LLVMBuildBr(builder, after_bb);
      LLVMPositionBuilderAtEnd(builder, after_bb);
    END;
    initck_npending := initck_npending - 1;
  END;
END;

PROCEDURE InitckHeapDispose(data: ADRMEM);
{ DISPOSE, before the free: retire the allocation's state, if any, so a
  reused address never inherits it (pas_initck_heap_dispose). }
BEGIN
  InitckHeapCall1('pas_initck_heap_dispose', data);
END;

PROCEDURE GuardInitckPointer(node: ADRMEM; si: INTEGER32; shadow: ADRMEM);
{ Selector si of designator node is a DEREF of tracked pointer storage whose
  leaf is shadow: reading the pointer is checked at the DEREF's own snapshot
  before the native pointer load, or its state joins the active value
  accumulator. A root pointer is named like a direct read of it. }
VAR
  sel: ADRMEM;
  symi: INTEGER32;
  what: Str255;
BEGIN
  sel := ArrItem(GetObj(node, 'selectors'), si);
  IF InitckEnabled(sel) THEN
  BEGIN
    what := 'component';
    IF si = 0 THEN
    BEGIN
      symi := LookupSym(GetStr(node, 'name'));
      what := 'local';
      IF symi <> 0 THEN
        IF symbols[symi].is_param THEN what := 'parameter'
        ELSE IF symbols[symi].is_with_field THEN what := 'field';
    END;
    GuardInitckState(shadow, what, InitckDesigPrefix(node, si), sel);
  END
  ELSE IF initck_taint <> NIL THEN
    NoteInitckState(LLVMBuildLoad2(builder, i1ty, shadow, MakeCStr('initck.src')));
END;

PROCEDURE DeclareVarInSpace(name: Str255; tk, address_space: INTEGER);
{ Declare ordinary storage in address space zero, or statically allocated
  NVPTX storage in the requested concrete device address space. A nonzero
  residence is a global even when its Pascal declaration is routine-local:
  CUDA shared/local/global/constant storage cannot be represented by a host
  stack alloca. }
VAR
  gvar, zero: ADRMEM;
  i, base: INTEGER32;
  dup, reuse_decl: BOOLEAN;
  uname, global_name, state_name: Str255;
BEGIN
  uname := UpperStr(name);
  { Only the current scope's own slice of the symbol table can collide --
    a local is allowed (expected, even) to shadow an outer/global variable
    of the same name, matching ordinary Pascal scoping. }
  base := CurScopeBase;
  dup := FALSE;
  reuse_decl := FALSE;
  FOR i := base + 1 TO nsymbols DO
    IF UpperStr(symbols[i].name) = uname THEN dup := TRUE;
  IF dup THEN
  BEGIN
    { An IMPLEMENTATION repeats interface VAR declarations.  The spliced
      header created an external declaration; this is its one definition. }
    IF (NOT in_local_scope) AND defining_implementation AND
       (NOT lowering_spliced_interface) THEN
    BEGIN
      gvar := symbols[LookupSym(name)].llvm_val;
      IF (TypeKind(tk) = TK_ARRAY) OR (TypeKind(tk) = TK_RECORD) OR
         (TypeKind(tk) = TK_LSTRING) OR (TypeKind(tk) = TK_POINTER) OR
         (TypeKind(tk) = TK_STRING) OR (TypeKind(tk) = TK_SET) OR
         (TypeKind(tk) = TK_FILE) OR (TypeKind(tk) = TK_VECTOR) OR
         (tk = TK_ADRMEM) THEN
        zero := LLVMConstNull(LLVMTypeForTk(tk))
      ELSE IF (tk = TK_REAL) OR (tk = TK_REAL32) THEN zero := LLVMConstReal(LLVMTypeForTk(tk), 0.0)
      ELSE zero := LLVMConstInt(LLVMTypeForTk(tk), 0, 0);
      LLVMSetInitializer(gvar, zero);
      reuse_decl := TRUE;
    END;
    IF NOT reuse_decl THEN
      AbortWith2('codegen: duplicate declaration: ', name);
  END;
  IF NOT reuse_decl THEN
  BEGIN
    IF in_local_scope AND (address_space = 0) THEN
      gvar := EntryAlloca(LLVMTypeForTk(tk), name)
    ELSE
    BEGIN
      global_name := name;
      IF in_local_scope THEN
      BEGIN
        global_name := cur_routine_name;
        global_name[0] := CHR(ORD(global_name[0]) + 1);
        global_name[ORD(global_name[0])] := '.';
        CONCAT(global_name, name);
      END;
      IF address_space = 0 THEN
        gvar := LLVMAddGlobal(modl, LLVMTypeForTk(tk), MakeCStr(global_name))
      ELSE
        gvar := LLVMAddGlobalInAddressSpace(modl, LLVMTypeForTk(tk),
                                            MakeCStr(global_name), address_space);
      IF NOT lowering_spliced_interface THEN
      BEGIN
        IF (TypeKind(tk) = TK_ARRAY) OR (TypeKind(tk) = TK_RECORD) OR
           (TypeKind(tk) = TK_LSTRING) OR (TypeKind(tk) = TK_POINTER) OR
           (TypeKind(tk) = TK_STRING) OR (TypeKind(tk) = TK_SET) OR
           (TypeKind(tk) = TK_FILE) OR (TypeKind(tk) = TK_VECTOR) OR
           (tk = TK_ADRMEM) THEN
          zero := LLVMConstNull(LLVMTypeForTk(tk))
        ELSE IF (tk = TK_REAL) OR (tk = TK_REAL32) THEN zero := LLVMConstReal(LLVMTypeForTk(tk), 0.0)
        ELSE zero := LLVMConstInt(LLVMTypeForTk(tk), 0, 0);
        LLVMSetInitializer(gvar, zero);
      END;
    END;
    IF TypeKind(tk) = TK_VECTOR THEN
      { A vector's storage gets LLVM's natural vector ABI alignment
        (TypeAlignBytes), so the alloca/global and every access through it
        match what the datalayout gives the type -- the vector_types
        checklit fixture pins the emitted alloca text. }
      LLVMSetAlignment(gvar, TypeAlignBytes(tk));
    IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
    nsymbols := nsymbols + 1;
    symbols[nsymbols].name := name;
    symbols[nsymbols].tk := tk;
    symbols[nsymbols].llvm_val := gvar;
    symbols[nsymbols].init_state := NIL;
    symbols[nsymbols].is_param := FALSE;
    symbols[nsymbols].is_with_field := FALSE;
    symbols[nsymbols].init_shared := FALSE;
    { Exact semantic types only (TypeKind would also admit subranges), and
      fixed aggregates built only from them. Allocate independently of
      declaration/read flags so a later enabled read can use the same
      state. DEVICE includes the CPU-device path. }
    IF in_local_scope AND (address_space = 0) AND
       (NOT is_device_compiland) AND (InitckShadowSize(tk) > 0) THEN
    BEGIN
      state_name := 'initck.';
      CONCAT(state_name, name);
      symbols[nsymbols].init_state := EntryAlloca(InitckShadowTy(tk), state_name);
      { Declaration lowering is in the routine prologue. Each invocation,
        including recursion, resets metadata without touching program bytes.
        Ordinary locals have no language-defined initializer/default; an
        aggregate starts with every leaf unset. }
      LLVMBuildStore(builder, LLVMConstNull(InitckShadowTy(tk)),
                     symbols[nsymbols].init_state);
    END;
  END;
END;

PROCEDURE DeclareVar(name: Str255; tk: INTEGER);
BEGIN
  DeclareVarInSpace(name, tk, 0);
END;

FUNCTION InitckFileElem(arg: ADRMEM): INTEGER;
{ The component type of the file a bare file argument names, when its
  buffer carries state; else 0. }
VAR
  symi: INTEGER32;
  tid: INTEGER;
BEGIN
  InitckFileElem := 0;
  symi := LookupSym(GetStr(arg, 'name'));
  IF (symi <> 0) AND NOT is_device_compiland THEN
  BEGIN
    tid := symbols[symi].tk;
    IF TypeKind(tid) = TK_FILE THEN
      IF InitckShadowSize(types[tid].elem_tid) > 0 THEN InitckFileElem := types[tid].elem_tid;
  END;
END;

PROCEDURE InitckGuardPut(arg, fcb: ADRMEM);
{ PUT(F) consumes the buffer's whole component: an enabled PUT requires
  every leaf initialized before the runtime writes it (afterwards the
  buffer is undefined again, set_mode_flags). }
VAR
  elem: INTEGER;
  what: Str255;
BEGIN
  elem := InitckFileElem(arg);
  IF (elem <> 0) AND InitckEnabled(arg) THEN
  BEGIN
    what := GetStr(arg, 'name');
    AppendChar(what, '^');
    GuardInitckCond(InitckAllState(InitckFileState(fcb), elem), 'part of', what, arg);
  END;
END;

FUNCTION InitckFileState(fcb: ADRMEM): ADRMEM;
{ A file buffer's INITCK leaf states (field 10 of the FCB, InitFileStorage);
  only for a component type with state. }
VAR
  gep_idx: ADRMEM;
BEGIN
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, LLVMConstInt(i32ty, 0, 0));
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 10, 0));
  InitckFileState := LLVMBuildLoad2(builder, i8ptrty,
    LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr('')), MakeCStr('initck.filebuf'));
END;

FUNCTION LoadFileFcbPtr(name: Str255): ADRMEM;
{ Loads a FILE variable's opaque i8* handle and bitcasts it to filefcbty*. }
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

{ ============================ routine table =============================== }

FUNCTION RoutineIsFunc(routi: INTEGER32): BOOLEAN;
{ Guards the routines[routi] index itself (routi = 0 means "not found"),
  since plain AND is not short-circuit in this dialect -- a single
  `(routi <> 0) AND routines[routi].is_func` expression would still
  evaluate routines[0], reading out of bounds on this 1-based array. }
BEGIN
  IF routi = 0 THEN
    RoutineIsFunc := FALSE
  ELSE
    RoutineIsFunc := routines[routi].is_func;
END;

FUNCTION FuncRetAggClass(routi: INTEGER32): INTEGER;
{ SYSV_CLASS_MEMORY / SYSV_CLASS_COERCED for any FUNCTION (plain Pascal or
  [C] FOREIGN alike) that returns an aggregate by value, and 0 for
  everything else (a PROCEDURE or a scalar-returning function). Recomputed
  from ret_tk on demand rather than cached in RoutineRec, exactly as the
  parameter side recomputes ClassifyAggregate at each of its sites, so the
  declaration and the call site can never disagree about the shape.
  routi = 0 ("not found") is guarded here for the same non-short-circuit-AND
  reason RoutineIsFunc documents. }
BEGIN
  FuncRetAggClass := 0;
  IF routi <> 0 THEN
    IF routines[routi].is_func THEN
      IF IsAggregateTk(routines[routi].ret_tk) THEN
        FuncRetAggClass := SysVAggClass(routines[routi].ret_tk);
END;


BEGIN
END.
