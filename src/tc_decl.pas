{ Pascal-1981 Native Type Checker implementation in extended IBM Pascal 2.0
  dialect. Consumes the JSON AST stream produced by pascal1981-parse on
  standard input, walks it validating the vintage-dialect core rule set
  (declarations, assignment/argument compatibility, ordinal-type rules,
  WORD/INTEGER coercion, aggregate string types), and re-emits the same
  tree on standard output. On any error it prints diagnostics to stderr
  and exits 1 without emitting AST JSON, matching cli_typecheck.py.

  Scope (v1): the rule set exercised by tests/fixtures/typecheck/, plus
  enough of the C-ABI/UNIT/pointer surface to self-host lex+parse+typecheck
  on this repository's own native .pas sources (lexer.pas, parser.pas,
  jsonutil.pas, and this file) end to end: EXTERN/FORWARD declarations (no
  body to check -- the real definition is a separately-compiled/linked
  object, or comes later in the same file), the ADRMEM/CPTR address types
  and the CINT/CCHAR/CSHORT/CLONG/CSIZE_T/CDOUBLE C-ABI width aliases, the
  wide INTEGER8/16/32/64 and WORD8/16/32/64 extension names (with exact
  integer width and signedness retained), the REAL32/64 extension names, the
  local_interfaces a USES clause splices in (their TYPE/PROC/FUNC
  signatures are registered exactly like an EXTERN decl's), pointer
  arithmetic (POINTER +/- an ordinal offset) and dereference (`p^`), STRING/
  LSTRING character indexing (`s[i]`), the ORD/CHR/TRUNC/ROUND/SIZEOF/ODD/
  SUCC/PRED/ABS/SQR/SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT/HIBYTE/LOBYTE/WRD/
  WRD8/BYWORD builtins, and non-PROGRAM compilation units (MODULE/INTERFACE/
  IMPLEMENTATION, which put `decls` directly on the root instead of nesting
  under a `block` the way a PROGRAM does -- see CheckUnit). This stage also
  checks DEVICE context, VARARGS attributes, UNIT interface/implementation
  signatures, and the extended type/C-ABI gates.

  Self-hosting note: as of the pointer/aux2-chaining and ImplementationUnit
  fixes, lexer.pas, parser.pas, jsonutil.pas, and typechecker.pas itself
  all type-check cleanly end to end through the native
  lexer_native|parser_native|typechecker_native pipeline (exit 0, valid
  annotated AST out), matching the Python reference's accept/reject verdict
  in every case. The one design point worth calling out: a FUNCTION's own
  name is deliberately NOT registered as a symbol-table entry to support
  `F := expr` inside F's body (see cur_func_name below) -- an earlier
  version shadowed F's own callable FUNC entry with a VAR entry for this
  purpose, which broke every recursive self-call within F's own body
  (LookupSymbol's backward scan found the shadow VAR first, so `F(x)`
  resolved to a variable reference instead of a call). This repository's
  own parser.pas relies on exactly this pattern (e.g. ParseConstant calling
  itself for nested array/set-literal elements).

  Annotation contract: the Python reference stamps a `resolved_type`
  attribute onto most (not textually all -- see below) IntLiteral/
  RealLiteral nodes (and the operand of a signed IntLiteral unary +/-),
  naming the literal's width/precision for codegen. Contextual annotation
  is completed by the integer range-checking pass. One functionally harmless
  gap remains against byte-identical parity with the Python reference:
    1. The Python reference itself does not tag perfectly consistently --
       e.g. a second `len := 0;` inside a nested IF's compound statement,
       assigning the exact same IntLiteral(0) to the exact same INTEGER
       variable as an earlier top-level `len := 0;` that DOES get tagged,
       is left untagged (verified against a minimal repro, not a
       self-hosting-only artifact). This stage tags every IntLiteral/
       RealLiteral node unconditionally instead, which is a strict, more
       internally-consistent superset of the Python reference's output
       rather than a divergent subset -- native never lacks a tag Python
       has, only (rarely) has one Python omits. }

{ Declaration and unit checking implementation. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_types.inc'*)
(*$INCLUDE:'tc_expr.inc'*)
(*$INCLUDE:'tc_stmt.inc'*)
(*$INCLUDE:'tc_decl.inc'*)
IMPLEMENTATION OF tc_decl;

FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateBool(b: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_ReplaceItemInObject(obj: ADRMEM; key: ADRMEM; newitem: ADRMEM): CINT [C]; EXTERN;

FUNCTION HasExternMarkerDecl(decl: ADRMEM): BOOLEAN; FORWARD;
FUNCTION IsForeignRoutineDecl(decl: ADRMEM): BOOLEAN; FORWARD;

VAR
  device_export_names: ARRAY [1..MAX_SYMBOLS] OF Str255;
  ndevice_exports: INTEGER32;

FUNCTION IsDeviceExport(name: Str255): BOOLEAN;
VAR
  i: INTEGER32;
  found: BOOLEAN;
  target, candidate: Str255;
BEGIN
  found := FALSE;
  target := UpperStr(name);
  FOR i := 1 TO ndevice_exports DO
  BEGIN
    candidate := UpperStr(device_export_names[i]);
    IF candidate = target THEN found := TRUE;
  END;
  IsDeviceExport := found;
END;

PROCEDURE LoadDeviceExports(root: ADRMEM);
VAR
  iface, params: ADRMEM;
  i, n: INTEGER32;
BEGIN
  ndevice_exports := 0;
  iface := GetObjOrNil(root, 'interface');
  IF GetBool(root, 'is_device') AND (iface <> NIL) THEN
  BEGIN
    params := GetObjOrNil(iface, 'params');
    IF params <> NIL THEN
    BEGIN
      n := cJSON_GetArraySize(params);
      FOR i := 0 TO n - 1 DO
        IF ndevice_exports < MAX_SYMBOLS THEN
        BEGIN
          ndevice_exports := ndevice_exports + 1;
          device_export_names[ndevice_exports] :=
            CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(params, i)));
        END;
    END;
  END;
END;

PROCEDURE MarkDeviceExports(root: ADRMEM);
VAR
  decls, decl: ADRMEM;
  i, n: INTEGER32;
  nt: Str255;
  rc: CINT;
BEGIN
  decls := GetObjOrNil(root, 'decls');
  IF decls <> NIL THEN
  BEGIN
    n := cJSON_GetArraySize(decls);
    FOR i := 0 TO n - 1 DO
    BEGIN
      decl := cJSON_GetArrayItem(decls, i);
      nt := NodeType(decl);
      IF ((nt = 'ProcDecl') OR (nt = 'FuncDecl')) AND
         IsDeviceExport(GetStr(decl, 'name')) THEN
        rc := cJSON_ReplaceItemInObject(decl, MakeCStr('is_exported_entry'),
                                        cJSON_CreateBool(1));
    END;
  END;
END;

FUNCTION FoldTuningIntLiteral(node: ADRMEM; VAR literal_value: INTEGER32): BOOLEAN;
VAR
  nt, op: Str255;
  inner: INTEGER32;
BEGIN
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN
  BEGIN
    literal_value := GetInt(node, 'value');
    FoldTuningIntLiteral := TRUE;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    op := GetStr(node, 'op');
    IF ((op = 'PLUS') OR (op = 'MINUS')) AND
       FoldTuningIntLiteral(GetObj(node, 'operand'), inner) THEN
    BEGIN
      IF op = 'MINUS' THEN literal_value := -inner ELSE literal_value := inner;
      FoldTuningIntLiteral := TRUE;
    END
    ELSE
      FoldTuningIntLiteral := FALSE;
  END
  ELSE
    FoldTuningIntLiteral := FALSE;
END;

PROCEDURE CheckLaunchBoundAttrs(decl: ADRMEM; is_function: BOOLEAN);
VAR
  attrs, attr, args: ADRMEM;
  i, j, nattrs, nargs: INTEGER32;
  nm: Str255;
  has_maxntid, has_reqntid, valid, folded: BOOLEAN;
  literal_value, axis_max, total: INTEGER32;
BEGIN
  attrs := GetObj(decl, 'attributes');
  nattrs := cJSON_GetArraySize(attrs);
  has_maxntid := FALSE;
  has_reqntid := FALSE;
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    nm := GetStr(cJSON_GetArrayItem(attrs, i), 'name');
    IF nm = 'MAXNTID' THEN has_maxntid := TRUE;
    IF nm = 'REQNTID' THEN has_reqntid := TRUE;
  END;
  IF has_maxntid AND has_reqntid AND
     (active_features.tuning_hints OR is_device_compiland) AND
     is_device_compiland THEN
    AddError('[MAXNTID] and [REQNTID] cannot be used together on the same kernel');

  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    attr := cJSON_GetArrayItem(attrs, i);
    nm := GetStr(attr, 'name');
    IF (nm = 'MAXNTID') OR (nm = 'REQNTID') OR (nm = 'MINCTASM') THEN
    BEGIN
      IF NOT (active_features.tuning_hints OR is_device_compiland) THEN
        AddError2('Launch-bound attribute requires the extended dialect: ', nm)
      ELSE IF NOT is_device_compiland THEN
        AddError2('Launch-bound attribute is only valid in DEVICE code: ', nm)
      ELSE IF is_function THEN
        AddError2('Launch-bound attribute is only valid on PROCEDUREs: ', nm)
      ELSE IF NOT (GetBool(decl, 'is_exported_entry') OR
                   IsDeviceExport(GetStr(decl, 'name'))) THEN
        AddError2('Launch-bound attribute requires an exported kernel procedure: ', nm)
      ELSE BEGIN
        args := GetObj(attr, 'arg');
        nargs := cJSON_GetArraySize(args);
        IF ((nm = 'MINCTASM') AND (nargs <> 1)) OR
           ((nm <> 'MINCTASM') AND ((nargs < 1) OR (nargs > 3))) THEN
          AddError2('Invalid launch-bound dimension argument count: ', nm)
        ELSE BEGIN
          valid := TRUE;
          total := 1;
          FOR j := 0 TO nargs - 1 DO
          BEGIN
            literal_value := 0;
            folded := FoldTuningIntLiteral(cJSON_GetArrayItem(args, j), literal_value);
            IF (NOT folded) OR (literal_value < 1) THEN
            BEGIN
              AddError2('Launch-bound dimensions must be positive integer literals: ', nm);
              valid := FALSE;
            END
            ELSE IF nm <> 'MINCTASM' THEN
            BEGIN
              IF j < 2 THEN axis_max := 1024 ELSE axis_max := 64;
              IF literal_value > axis_max THEN
              BEGIN
                AddError2('Launch-bound dimension exceeds the CUDA architectural maximum: ', nm);
                valid := FALSE;
              END
              ELSE
                total := total * literal_value;
            END;
          END;
          IF valid AND (nm <> 'MINCTASM') AND (total > 1024) THEN
            AddError2('Launch-bound total threads exceed the CUDA architectural maximum: ', nm);
        END;
      END;
    END;
  END;
END;

{ ============================== declarations ============================ }

PROCEDURE CheckBlock(block: ADRMEM); FORWARD;

FUNCTION HasExtendedConstIntrinsic(node: ADRMEM): BOOLEAN;
VAR
  nm: Str255;
  args: ADRMEM;
  i, n: INTEGER32;
BEGIN
  HasExtendedConstIntrinsic := FALSE;
  IF NodeType(node) = 'FuncCall' THEN
  BEGIN
    nm := UpperStr(GetStr(node, 'name'));
    IF (nm = 'ORD') OR (nm = 'CHR') OR (nm = 'SUCC') OR (nm = 'PRED') THEN
      HasExtendedConstIntrinsic := TRUE
    ELSE
    BEGIN
      args := GetObj(node, 'args');
      n := cJSON_GetArraySize(args);
      FOR i := 0 TO n - 1 DO
        IF HasExtendedConstIntrinsic(cJSON_GetArrayItem(args, i)) THEN
          HasExtendedConstIntrinsic := TRUE;
    END;
  END;
END;

PROCEDURE CheckConstOrdinalBounds(node: ADRMEM);
VAR
  nm: Str255;
  args: ADRMEM;
  folded_value: INTEGER64;
  arg_tk: INTEGER;
BEGIN
  IF NodeType(node) = 'FuncCall' THEN
  BEGIN
    nm := UpperStr(GetStr(node, 'name'));
    args := GetObj(node, 'args');
    IF ((nm = 'SUCC') OR (nm = 'PRED')) AND (cJSON_GetArraySize(args) = 1) THEN
    BEGIN
      arg_tk := CheckExpr(cJSON_GetArrayItem(args, 0));
      IF FoldConstInt(cJSON_GetArrayItem(args, 0), folded_value) THEN
      BEGIN
        IF nm = 'SUCC' THEN folded_value := folded_value + 1 ELSE folded_value := folded_value - 1;
        IF (arg_tk = TK_INTEGER) AND ((folded_value < -32767) OR (folded_value > 32767)) THEN
        BEGIN
          IF nm = 'SUCC' THEN AddError('Constant SUCC result outside INTEGER range')
          ELSE AddError('Constant PRED result outside INTEGER range');
        END
        ELSE IF (arg_tk = TK_CHAR) AND ((folded_value < 0) OR (folded_value > 255)) THEN
        BEGIN
          IF nm = 'SUCC' THEN AddError('Constant SUCC result outside CHAR range')
          ELSE AddError('Constant PRED result outside CHAR range');
        END;
      END;
    END;
  END;
END;

PROCEDURE CheckDecl(decl: ADRMEM);
VAR
  nt, dname: Str255;
  names_arr, type_expr, params_arr, body, ret_type_node: ADRMEM;
  tk, aux, aux2, idx_tk, ret_tk: INTEGER;
  n, i: INTEGER32;
  nm: Str255;
  si: INTEGER32;
  np, pi, ppi: INTEGER32;
  param, pnames: ADRMEM;
  ptk, paux, paux2, pidx: INTEGER;
  pn, pj: INTEGER32;
  saved_func_name: Str255;
  saved_func_ret_tk, saved_func_aux, saved_func_aux2: INTEGER;
  attrs_arr, attr_item: ADRMEM;
  nattrs, ai: INTEGER32;
  is_vararg, has_c: BOOLEAN;
  has_block_body: BOOLEAN;
  prior: INTEGER32;
  const_value: INTEGER64;
BEGIN
  nt := NodeType(decl);
  IF nt = 'VarDecl' THEN
  BEGIN
    names_arr := GetObj(decl, 'names');
    type_expr := GetObj(decl, 'type_expr');
    ResolveTypeExpr(type_expr, tk, aux, aux2, idx_tk);
    n := cJSON_GetArraySize(names_arr);
    FOR i := 0 TO n - 1 DO
    BEGIN
      nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, i)));
      si := DefineSymbol(nm, 'VAR', tk, aux, aux2, idx_tk);
    END;
  END
  ELSE IF nt = 'ConstDecl' THEN
  BEGIN
    dname := GetStr(decl, 'name');
    IF HasExtendedConstIntrinsic(GetObj(decl, 'value')) AND
       NOT active_features.extended_const_intrinsics THEN
      AddError('CONST intrinsic calls require the extended-const-intrinsics feature');
    tk := CheckExpr(GetObj(decl, 'value'));
    CheckConstOrdinalBounds(GetObj(decl, 'value'));
    si := DefineSymbol(dname, 'CONST', tk, 0, 0, 0);
    IF FoldConstInt(GetObj(decl, 'value'), const_value) THEN
    BEGIN
      symbols[si].has_const_int := TRUE;
      symbols[si].const_int := const_value;
    END;
  END
  ELSE IF nt = 'TypeDecl' THEN
  BEGIN
    dname := GetStr(decl, 'name');
    type_expr := GetObj(decl, 'type_expr');
    ResolveTypeExpr(type_expr, tk, aux, aux2, idx_tk);
    IF ntypes < MAX_TYPES THEN
    BEGIN
      ntypes := ntypes + 1;
      types[ntypes].name := dname;
      types[ntypes].tk := tk;
      types[ntypes].aux := aux;
      types[ntypes].aux2 := aux2;
      types[ntypes].idx_tk := idx_tk;
    END;
    IF NodeType(type_expr) = 'EnumType' THEN
    BEGIN
      { An enum's member identifiers are constants of the enum type, in
        declaration order -- registered here so a member resolves as a
        value wherever an identifier is legal (the typechecker half of
        what codegen.pas's const_tbl registration does for folding). }
      names_arr := GetObj(type_expr, 'values');
      n := cJSON_GetArraySize(names_arr);
      FOR i := 0 TO n - 1 DO
      BEGIN
        nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, i)));
        si := DefineSymbol(nm, 'CONST', TK_ENUM, 0, 0, 0);
      END;
    END;
  END
  ELSE IF (nt = 'ProcDecl') OR (nt = 'FuncDecl') THEN
  BEGIN
    dname := GetStr(decl, 'name');
    params_arr := GetObj(decl, 'params');
    np := cJSON_GetArraySize(params_arr);
    IF nt = 'FuncDecl' THEN
    BEGIN
      ret_type_node := GetObj(decl, 'return_type');
      ResolveTypeExpr(ret_type_node, ret_tk, aux, aux2, idx_tk);
    END
    ELSE
      ret_tk := TK_VOID;

    { EXTERN promises the body lives in another compiland, so supplying one
      here is an error rather than the completion of a placeholder -- that is
      what FORWARD is for. The reference rejects this at the same layer
      (typecheck/decls.py: only a FORWARD sets is_forward, so a body-bearing
      redeclaration falls through to "already declared").

      Deliberately narrow: a prior EXTERN *in this same scope*, and only when
      this declaration actually carries a body. Everything else that
      legitimately redeclares a name stays legal -- FORWARD then body, a
      spliced INTERFACE header then the IMPLEMENTATION's body, and the
      manual's split-implementation form where an IMPLEMENTATION redeclares
      an interface routine `; EXTERN;` because the body is in another
      compiland. That last one has no body of its own, so the
      has_block_body half already excludes it. Plain AND is not
      short-circuit in this dialect, hence the nested IFs rather than one
      conjunction.

      A body-less declaration is *not* a NIL 'body' slot: the parser writes
      the slot with AddNullField (parser.pas:2329), and jsonutil.pas's
      GetObj hands back that cJSON null item unchanged, so `body <> NIL` is
      true for every routine decl ever parsed. Test the node type instead,
      exactly as cg_decl.pas:978 does for the same question. }
    body := GetObj(decl, 'body');
    has_block_body := NodeType(body) = 'Block';
    prior := LookupSymbolInScope(dname);
    IF prior >= 1 THEN
      IF symbols[prior].is_extern THEN
        IF has_block_body THEN
          AddError2('EXTERN routine cannot be defined here (use FORWARD): ', dname);

    si := DefineSymbol(dname, nt, TK_UNKNOWN, 0, 0, 0);
    IF nt = 'FuncDecl' THEN
      symbols[si].kind := 'FUNC'
    ELSE
      symbols[si].kind := 'PROC';
    symbols[si].ret_tk := ret_tk;
    symbols[si].is_extern := HasExternMarkerDecl(decl);
    ppi := 0;
    FOR pi := 0 TO np - 1 DO
    BEGIN
      param := cJSON_GetArrayItem(params_arr, pi);
      ResolveTypeExpr(GetObj(param, 'type_expr'), ptk, paux, paux2, pidx);
      pnames := GetObj(param, 'names');
      pn := cJSON_GetArraySize(pnames);
      FOR pj := 0 TO pn - 1 DO
      BEGIN
        ppi := ppi + 1;
        IF ppi <= MAX_PARAMS THEN
          symbols[si].param_tk[ppi] := ptk;
      END;
    END;
    { ppi (a parameter count, always small) is INTEGER32; nparams is
      INTEGER, and the language has no implicit INTEGER32 -> INTEGER
      narrowing -- RETYPE makes the deliberate truncation explicit. }
    symbols[si].nparams := RETYPE(INTEGER, ppi);

    { [VARARGS] marks the declared parameter list as a fixed prefix only.
      Attribute names are already canonical uppercase in the AST (see
      parser.pas ParseAttributeItem), so no case-folding is needed. }
    is_vararg := FALSE;
    has_c := FALSE;
    attrs_arr := GetObj(decl, 'attributes');
    nattrs := cJSON_GetArraySize(attrs_arr);
    FOR ai := 0 TO nattrs - 1 DO
    BEGIN
      attr_item := cJSON_GetArrayItem(attrs_arr, ai);
      nm := GetStr(attr_item, 'name');
      IF nm = 'VARARGS' THEN is_vararg := TRUE;
      { The parser canonicalizes both [C] and [CDECL] to a one-character
        LSTRING. A CHAR literal cannot compare directly with that aggregate. }
      IF (ORD(nm[0]) = 1) AND (nm[1] = 'C') THEN has_c := TRUE;
    END;
    IF has_c AND (NOT FeaturesAreExtended(active_features)) THEN
      AddError2('The [C] attribute requires the extended dialect: ', dname);
    IF is_vararg AND (NOT FeaturesAreExtended(active_features)) THEN
      AddError2('The [VARARGS] attribute requires the extended dialect: ', dname);
    IF is_vararg AND (NOT has_c) THEN
      AddError2('[VARARGS] requires the [C] attribute: ', dname);
    IF is_vararg AND is_device_compiland THEN
      AddError2('[VARARGS] is not permitted in DEVICE code: ', dname);
    CheckLaunchBoundAttrs(decl, nt = 'FuncDecl');
    symbols[si].is_vararg := is_vararg;

    { Check the routine body (if any) in its own scope, with parameters
      bound and -- for a FUNCTION -- cur_func_name/cur_func_ret_tk/aux/aux2
      set so `F := expr` inside F's own body resolves as a return-slot
      assignment (see CheckStmt's AssignStmt case) without a shadow symbol
      that would otherwise hide F's own FUNC entry from recursive calls.
      Same null-slot caveat as the EXTERN check above -- a body-less decl
      reaches here with a non-NIL cJSON null, not NIL. }
    IF has_block_body THEN
    BEGIN
      PushScope;
      saved_func_name := cur_func_name;
      saved_func_ret_tk := cur_func_ret_tk;
      saved_func_aux := cur_func_aux;
      saved_func_aux2 := cur_func_aux2;
      IF nt = 'FuncDecl' THEN
      BEGIN
        cur_func_name := dname;
        cur_func_ret_tk := ret_tk;
        cur_func_aux := aux;
        cur_func_aux2 := aux2;
      END
      ELSE
        cur_func_name := '';
      ppi := 0;
      FOR pi := 0 TO np - 1 DO
      BEGIN
        param := cJSON_GetArrayItem(params_arr, pi);
        ResolveTypeExpr(GetObj(param, 'type_expr'), ptk, paux, paux2, pidx);
        pnames := GetObj(param, 'names');
        pn := cJSON_GetArraySize(pnames);
        FOR pj := 0 TO pn - 1 DO
        BEGIN
          nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(pnames, pj)));
          si := DefineSymbol(nm, 'VAR', ptk, paux, paux2, pidx);
        END;
      END;
      CheckBlock(body);
      cur_func_name := saved_func_name;
      cur_func_ret_tk := saved_func_ret_tk;
      cur_func_aux := saved_func_aux;
      cur_func_aux2 := saved_func_aux2;
      PopScope;
    END;
  END;
END;

PROCEDURE CheckBlock(block: ADRMEM);
VAR
  decls_arr, body_arr: ADRMEM;
  n, i: INTEGER32;
BEGIN
  decls_arr := GetObj(block, 'decls');
  n := cJSON_GetArraySize(decls_arr);
  FOR i := 0 TO n - 1 DO
    CheckDecl(cJSON_GetArrayItem(decls_arr, i));
  body_arr := GetObj(block, 'body');
  CheckStmtList(body_arr);
END;

FUNCTION SameIdentifier(a, b: Str255): BOOLEAN;
{ Case-insensitive identifier comparison -- a USES clause is matched against
  a UNIT heading written in a different file, where the two spellings
  routinely differ in case, matching codegen.pas's own SameIdentifier. }
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

FUNCTION FindUnitIface(ifaces: ADRMEM; unit_name: Str255): ADRMEM;
{ The local_interfaces entry named unit_name (case-insensitive), or NIL. }
VAR
  n, i: INTEGER32;
  found: ADRMEM;
BEGIN
  found := NIL;
  IF ifaces <> NIL THEN
  BEGIN
    n := cJSON_GetArraySize(ifaces);
    FOR i := 0 TO n - 1 DO
      IF SameIdentifier(GetStr(cJSON_GetArrayItem(ifaces, i), 'name'), unit_name) THEN
        found := cJSON_GetArrayItem(ifaces, i);
  END;
  FindUnitIface := found;
END;

VAR
  rs_is_func: BOOLEAN; { scratch result cells for ResolveRoutineSignature,
    read immediately by its caller before the next call overwrites them --
    avoids needing a VAR array parameter (this dialect has no named array
    type to pass MAX_PARAMS-sized param_tk by reference with). }
  rs_nparams: INTEGER32;
  rs_param_tk: ARRAY [1..MAX_PARAMS] OF INTEGER;
  rs_ret_tk: INTEGER;
  rs_is_vararg: BOOLEAN;

PROCEDURE ResolveRoutineSignature(decl: ADRMEM);
{ Extracts a ProcDecl/FuncDecl's signature (kind, parameter types in
  declaration order, return type, VARARGS-ness) into the rs_* scratch cells
  -- the same resolution CheckDecl's own ProcDecl/FuncDecl case performs
  when registering a symbol, factored out so an interface declaration and
  its implementation counterpart can each be resolved and compared without
  registering either as a symbol. }
VAR
  params_arr, param, pnames, ret_type_node, attrs_arr, attr_item: ADRMEM;
  np, pi, ppi, pn, pj, nattrs, ai: INTEGER32;
  ptk, paux, paux2, pidx, aux, aux2, idx_tk: INTEGER;
BEGIN
  rs_is_func := NodeType(decl) = 'FuncDecl';
  params_arr := GetObj(decl, 'params');
  np := cJSON_GetArraySize(params_arr);
  IF rs_is_func THEN
  BEGIN
    ret_type_node := GetObj(decl, 'return_type');
    ResolveTypeExpr(ret_type_node, rs_ret_tk, aux, aux2, idx_tk);
  END
  ELSE
    rs_ret_tk := TK_VOID;
  ppi := 0;
  FOR pi := 0 TO np - 1 DO
  BEGIN
    param := cJSON_GetArrayItem(params_arr, pi);
    ResolveTypeExpr(GetObj(param, 'type_expr'), ptk, paux, paux2, pidx);
    pnames := GetObj(param, 'names');
    pn := cJSON_GetArraySize(pnames);
    FOR pj := 0 TO pn - 1 DO
    BEGIN
      ppi := ppi + 1;
      IF ppi <= MAX_PARAMS THEN rs_param_tk[ppi] := ptk;
    END;
  END;
  rs_nparams := ppi;
  rs_is_vararg := FALSE;
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := cJSON_GetArraySize(attrs_arr);
  FOR ai := 0 TO nattrs - 1 DO
  BEGIN
    attr_item := cJSON_GetArrayItem(attrs_arr, ai);
    IF GetStr(attr_item, 'name') = 'VARARGS' THEN rs_is_vararg := TRUE;
  END;
END;

FUNCTION FindProcFuncDeclByName(decls_arr: ADRMEM; name: Str255): ADRMEM;
VAR
  n, i: INTEGER32;
  decl: ADRMEM;
  nt: Str255;
  found: ADRMEM;
BEGIN
  found := NIL;
  n := cJSON_GetArraySize(decls_arr);
  FOR i := 0 TO n - 1 DO
  BEGIN
    decl := cJSON_GetArrayItem(decls_arr, i);
    nt := NodeType(decl);
    IF ((nt = 'ProcDecl') OR (nt = 'FuncDecl')) AND (GetStr(decl, 'name') = name) THEN
      found := decl;
  END;
  FindProcFuncDeclByName := found;
END;

FUNCTION FindVarDeclContainingName(decls_arr: ADRMEM; name: Str255): ADRMEM;
VAR
  n, i, m, j: INTEGER32;
  decl, names_arr: ADRMEM;
  found: ADRMEM;
BEGIN
  found := NIL;
  n := cJSON_GetArraySize(decls_arr);
  FOR i := 0 TO n - 1 DO
  BEGIN
    decl := cJSON_GetArrayItem(decls_arr, i);
    IF NodeType(decl) = 'VarDecl' THEN
    BEGIN
      names_arr := GetObj(decl, 'names');
      m := cJSON_GetArraySize(names_arr);
      FOR j := 0 TO m - 1 DO
        IF CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, j))) = name THEN
          found := decl;
    END;
  END;
  FindVarDeclContainingName := found;
END;

FUNCTION HasExternMarkerDecl(decl: ADRMEM): BOOLEAN;
{ True for a routine carrying an EXTERN/EXTERNAL marker in either of its two
  spellings -- the [EXTERN] attribute or the `; EXTERN;` directive. This is
  the "a body cannot legally appear for this name" question, and it is the
  one CheckDecl's is_extern must answer.

  The [C] attribute on its own is deliberately NOT enough here, unlike in
  IsForeignRoutineDecl below. [C] answers a different question -- "call this
  with the SysV C ABI" -- and by itself says nothing about where the body
  lives: `FUNCTION twice(x: CINT): CINT [C];` in an INTERFACE is an ordinary
  Pascal routine, exported with the C convention so C callers can reach it,
  whose body this compiland is expected to supply. Codegen agrees, setting
  routines[].is_extern from IsExternDirectiveDecl OR IsCForeignDecl
  (cg_decl.pas:1220), and IsCForeignDecl requires [C] *and* an extern
  marker. Marking bare [C] extern here rejected such a routine's own body
  with "EXTERN routine cannot be defined here" while codegen lowered it
  happily. }
VAR
  attrs_arr, item: ADRMEM;
  i, nattrs: INTEGER32;
  attr_nm, directive: Str255;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := cJSON_GetArraySize(attrs_arr);
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    item := cJSON_GetArrayItem(attrs_arr, i);
    attr_nm := GetStr(item, 'name');
    IF attr_nm = 'EXTERN' THEN found := TRUE;
    IF attr_nm = 'EXTERNAL' THEN found := TRUE;
  END;
  directive := GetStr(decl, 'directive');
  IF directive = 'EXTERN' THEN found := TRUE;
  IF directive = 'EXTERNAL' THEN found := TRUE;
  HasExternMarkerDecl := found;
END;

FUNCTION IsForeignRoutineDecl(decl: ADRMEM): BOOLEAN;
{ True for a routine an IMPLEMENTATION is not obliged to define, so that
  ValidateImplementationContract below does not demand a body for it:
  anything HasExternMarkerDecl accepts, plus a bare [C] declaration.

  The bare-[C] half is a concession to the established interface convention
  rather than a claim about the language. src/cg_base.inc declares all 123
  of its libc and LLVM-C entries as `FUNCTION LLVMBuildRet(...): ADRMEM [C];`
  with no EXTERN marker -- the marker is spelled only in the .pas program
  headers -- so under a marker-only rule this compiler fails to typecheck
  itself, every one of those entries reported as a missing implementation.
  ParseInterfaceDirectiveInto's acceptance of `; EXTERN;` inside an
  INTERFACE is new in this branch and the out-of-repo Python reference gen1
  builds with may not take it, so the .inc files cannot be respelled yet.

  The cost is that a bare-[C] routine genuinely meant to be defined in the
  IMPLEMENTATION escapes the export check, and a missing definition surfaces
  as a link-time undefined symbol instead. Once the .inc convention moves to
  an explicit marker, this predicate should collapse into
  HasExternMarkerDecl.

  Note this checks the interface's own declarations rather than filtering by
  the UNIT export list. The Python reference validates the contract by
  looping the export list instead, which would also let a [C] declaration
  through -- but it silently skips validation entirely for a unit written
  `UNIT foo;` with no parenthesised list, which is exactly the shape
  src/cg_base.inc uses. Exempting by kind keeps the contract enforced there. }
VAR
  attrs_arr, item: ADRMEM;
  i, nattrs: INTEGER32;
  attr_nm: Str255;
  found: BOOLEAN;
BEGIN
  found := HasExternMarkerDecl(decl);
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := cJSON_GetArraySize(attrs_arr);
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    item := cJSON_GetArrayItem(attrs_arr, i);
    attr_nm := GetStr(item, 'name');
    { A bare `attr_nm = 'C'` comparison doesn't typecheck: a single-quoted
      single-character literal lexes as CHAR, not a length-1 LSTRING, so
      LSTRING = CHAR has no defined comparison. Compare the length byte
      (index 0, per the LSTRING index-0-is-length-as-CHAR convention) and
      the first character instead -- same idiom as codegen_decl.inc:504. }
    IF (ORD(attr_nm[0]) = 1) AND (attr_nm[1] = 'C') THEN found := TRUE;
  END;
  IsForeignRoutineDecl := found;
END;

PROCEDURE ValidateRoutineExport(iface_decl, impl_decls: ADRMEM; name: Str255);
{ An exported PROCEDURE/FUNCTION needs a same-named, same-shaped definition
  in the IMPLEMENTATION -- missing entirely, or present with a different
  parameter count/type, return type, or VARARGS-ness, both compile clean
  through every earlier native stage and previously only surfaced (if at
  all) as a clang/linker error or a silently wrong ABI. Parameter *mode*
  (VAR/CONST/value) is deliberately not compared: this typechecker's own
  symbol table has never tracked per-parameter mode (see CheckDecl's
  ProcDecl/FuncDecl case), so there is nothing here to compare it against
  without extending SymRec for a dimension nothing else needs yet. }
VAR
  a_is_func, b_is_vararg: BOOLEAN;
  a_nparams: INTEGER32;
  a_param_tk: ARRAY [1..MAX_PARAMS] OF INTEGER;
  a_ret_tk: INTEGER;
  a_is_vararg: BOOLEAN;
  impl_decl: ADRMEM;
  k: INTEGER32;
  mismatch: BOOLEAN;
  msg: Str255;
BEGIN
  ResolveRoutineSignature(iface_decl);
  a_is_func := rs_is_func;
  a_nparams := rs_nparams;
  FOR k := 1 TO rs_nparams DO
    IF k <= MAX_PARAMS THEN a_param_tk[k] := rs_param_tk[k];
  a_ret_tk := rs_ret_tk;
  a_is_vararg := rs_is_vararg;

  impl_decl := FindProcFuncDeclByName(impl_decls, name);
  IF impl_decl = NIL THEN
  BEGIN
    msg := 'missing implementation for exported routine: ';
    CONCAT(msg, name);
    AddError(msg);
  END
  ELSE
  BEGIN
    ResolveRoutineSignature(impl_decl);
    mismatch := FALSE;
    IF rs_is_func <> a_is_func THEN mismatch := TRUE;
    IF rs_nparams <> a_nparams THEN
      mismatch := TRUE
    ELSE
      FOR k := 1 TO a_nparams DO
        IF (k <= MAX_PARAMS) AND (rs_param_tk[k] <> a_param_tk[k]) THEN mismatch := TRUE;
    IF rs_ret_tk <> a_ret_tk THEN mismatch := TRUE;
    IF rs_is_vararg <> a_is_vararg THEN mismatch := TRUE;
    IF mismatch THEN
    BEGIN
      msg := 'implementation signature does not match its interface declaration for: ';
      CONCAT(msg, name);
      AddError(msg);
    END;
  END;
END;

PROCEDURE ValidateVarExport(iface_type_expr, impl_decls: ADRMEM; name: Str255);
{ An exported VAR needs its own matching definition in the IMPLEMENTATION
  too (unlike TYPE/CONST, which are shared by reference from the spliced
  interface and never redeclared -- see jsonutil.pas, which never
  redeclares its own interface's Str255/CharBuf256/PCharBuf TYPEs): each
  compiland's `Counter` is its own global storage, and the two need to
  agree on its type for the extern declaration codegen emits in an
  importer to actually match what this compiland defines. }
VAR
  a_tk, a_aux, a_aux2, a_idx_tk: INTEGER;
  b_tk, b_aux, b_aux2, b_idx_tk: INTEGER;
  impl_decl: ADRMEM;
  msg: Str255;
BEGIN
  ResolveTypeExpr(iface_type_expr, a_tk, a_aux, a_aux2, a_idx_tk);
  impl_decl := FindVarDeclContainingName(impl_decls, name);
  IF impl_decl = NIL THEN
  BEGIN
    msg := 'missing implementation for exported VAR: ';
    CONCAT(msg, name);
    AddError(msg);
  END
  ELSE
  BEGIN
    ResolveTypeExpr(GetObj(impl_decl, 'type_expr'), b_tk, b_aux, b_aux2, b_idx_tk);
    IF (b_tk <> a_tk) OR (b_aux <> a_aux) OR (b_aux2 <> a_aux2) OR (b_idx_tk <> a_idx_tk) THEN
    BEGIN
      msg := 'implementation type does not match its interface declaration for: ';
      CONCAT(msg, name);
      AddError(msg);
    END;
  END;
END;

PROCEDURE ValidateImplementationContract(root, own_iface: ADRMEM);
{ own_iface is the spliced INTERFACE header matching this ImplementationUnit
  by name (found via FindUnitIface), or NIL for an IMPLEMENTATION with no
  matching spliced header at all -- codegen.pas's CheckUsesClauses-adjacent
  "needs a spliced INTERFACE header" diagnostic covers that gap already, so
  there is nothing further to validate here in that case. Every exported
  PROCEDURE/FUNCTION/VAR must have a matching, conformant declaration in
  root's own decls; TYPE/CONST are shared by reference from the splice and
  are deliberately not required to be redeclared (see ValidateVarExport), and
  a [C]/EXTERN routine is exempt because its body is in another object
  entirely (see IsForeignRoutineDecl). }
VAR
  iface_decls, impl_decls, decl, names_arr: ADRMEM;
  n, i, m, j: INTEGER32;
  dnt, nm: Str255;
BEGIN
  IF own_iface <> NIL THEN
  BEGIN
    iface_decls := GetObj(own_iface, 'decls');
    impl_decls := GetObj(root, 'decls');
    n := cJSON_GetArraySize(iface_decls);
    FOR i := 0 TO n - 1 DO
    BEGIN
      decl := cJSON_GetArrayItem(iface_decls, i);
      dnt := NodeType(decl);
      { A [C]/EXTERN routine is declared here only so callers can bind to it;
        its body is in a C library or another object, so it is exempt. }
      IF (dnt = 'ProcDecl') OR (dnt = 'FuncDecl') THEN
      BEGIN
        IF NOT IsForeignRoutineDecl(decl) THEN
          ValidateRoutineExport(decl, impl_decls, GetStr(decl, 'name'));
      END
      ELSE IF dnt = 'VarDecl' THEN
      BEGIN
        names_arr := GetObj(decl, 'names');
        m := cJSON_GetArraySize(names_arr);
        FOR j := 0 TO m - 1 DO
        BEGIN
          nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, j)));
          ValidateVarExport(GetObj(decl, 'type_expr'), impl_decls, nm);
        END;
      END;
    END;
  END;
END;

PROCEDURE CheckUnit(root: ADRMEM);
{ Only ProgramUnit nests its decls/body inside a 'block' object -- see
  ast_nodes.py's ProgramUnit vs ModuleUnit/InterfaceUnit/ImplementationUnit:
  the other three compilation-unit kinds put `decls` directly on the root,
  and only ImplementationUnit has executable statements at all (its
  optional `init_body`, a bare statement array, no 'body' *or* 'block' key
  -- an InterfaceUnit is signatures only). CheckBlock(GetObj(root,'block'))
  alone silently no-ops on every non-PROGRAM compilation unit, since
  GetObj/cJSON_GetArraySize both tolerate the resulting NIL/absent-key --
  which is exactly how jsonutil.pas's own IMPLEMENTATION body went entirely
  unchecked and unannotated until this was added. }
VAR
  nt: Str255;
  decls_arr, init_body: ADRMEM;
  n, i: INTEGER32;
  saved_device: BOOLEAN;
BEGIN
  saved_device := is_device_compiland;
  is_device_compiland := GetBool(root, 'is_device');
  nt := NodeType(root);
  IF nt = 'ProgramUnit' THEN
    CheckBlock(GetObj(root, 'block'))
  ELSE BEGIN
    decls_arr := GetObj(root, 'decls');
    n := cJSON_GetArraySize(decls_arr);
    FOR i := 0 TO n - 1 DO
      CheckDecl(cJSON_GetArrayItem(decls_arr, i));
    IF nt = 'ImplementationUnit' THEN
    BEGIN
      ValidateImplementationContract(root,
        FindUnitIface(GetObj(root, 'local_interfaces'), GetStr(root, 'name')));
      init_body := GetObj(root, 'init_body');
      IF init_body <> NIL THEN CheckStmtList(init_body);
    END;
  END;
  is_device_compiland := saved_device;
END;

{ ========================= local-interface support ======================== }
{ ReadAllStdin now lives in jsonutil. }

PROCEDURE BindUsesAlias(alias, ename: Str255);
{ `USES unit(alias)` binds alias to whatever ename (the export at that
  position in the unit's own heading) already resolved to when its real
  declaration was registered under its own name a moment ago -- see
  codegen.pas's own BindUsesAlias for why this is an *additional* symbol
  entry sharing the original's type info, not a rename of the original:
  the original name still has to typecheck too, since codegen still lowers
  every local_interfaces declaration under its real spelling. }
VAR
  si, ai, pi: INTEGER32;
BEGIN
  si := LookupSymbol(ename);
  IF si = 0 THEN
    AddError('USES import renames an export with no matching declaration')
  ELSE
  BEGIN
    ai := DefineSymbol(alias, symbols[si].kind, symbols[si].tk,
      symbols[si].aux, symbols[si].aux2, symbols[si].idx_tk);
    symbols[ai].nparams := symbols[si].nparams;
    FOR pi := 1 TO symbols[si].nparams DO
      symbols[ai].param_tk[pi] := symbols[si].param_tk[pi];
    symbols[ai].ret_tk := symbols[si].ret_tk;
    symbols[ai].is_vararg := symbols[si].is_vararg;
  END;
END;

PROCEDURE CheckLocalInterfaceUses(root, ifaces: ADRMEM);
{ Once every local_interfaces declaration has been registered under its own
  real name (CheckLocalInterfaces below), bind any renaming USES import's
  alias -- mirrors codegen.pas's own CheckUsesClauses imports handling, run
  at the equivalent point in the typechecker's own pass. }
VAR
  uses_arr, clause, imports_arr, params_arr: ADRMEM;
  nclauses, ci, nimports, ii, nparams: INTEGER32;
  unit_name, alias, ename: Str255;
BEGIN
  uses_arr := GetObj(root, 'uses');
  IF uses_arr <> NIL THEN
  BEGIN
    nclauses := cJSON_GetArraySize(uses_arr);
    FOR ci := 0 TO nclauses - 1 DO
    BEGIN
      clause := cJSON_GetArrayItem(uses_arr, ci);
      imports_arr := GetObjOrNil(clause, 'imports');
      IF imports_arr <> NIL THEN
      BEGIN
        unit_name := GetStr(clause, 'name');
        params_arr := GetObj(FindUnitIface(ifaces, unit_name), 'params');
        nparams := cJSON_GetArraySize(params_arr);
        nimports := cJSON_GetArraySize(imports_arr);
        IF nimports > nparams THEN
          AddError('USES import list renames more names than the unit exports')
        ELSE
          FOR ii := 0 TO nimports - 1 DO
          BEGIN
            alias := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(imports_arr, ii)));
            ename := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(params_arr, ii)));
            BindUsesAlias(alias, ename);
          END;
      END;
    END;
  END;
END;

PROCEDURE CheckLocalInterfaces(root: ADRMEM);
{ USES X splices X's INTERFACE into this file's local_interfaces list (see
  units.py's check_program_unit): each entry's decls are signature-only (no
  body -- the real IMPLEMENTATION is a separately-compiled/linked object), so
  running them through the ordinary CheckDecl dispatch registers their TYPEs
  and PROC/FUNC signatures as callable symbols exactly like an EXTERN decl,
  with no body to check. A renaming USES clause (`USES unit(alias, ...)`) is
  additionally honored by CheckLocalInterfaceUses, once every real name here
  is registered. }
VAR
  ifaces, decls_arr: ADRMEM;
  n, ni, m, di: INTEGER32;
  iface: ADRMEM;
  saved_device: BOOLEAN;
BEGIN
  ifaces := GetObj(root, 'local_interfaces');
  IF ifaces <> NIL THEN
  BEGIN
    n := cJSON_GetArraySize(ifaces);
    FOR ni := 0 TO n - 1 DO
    BEGIN
      iface := cJSON_GetArrayItem(ifaces, ni);
      saved_device := is_device_compiland;
      is_device_compiland := GetBool(iface, 'is_device');
      decls_arr := GetObj(iface, 'decls');
      m := cJSON_GetArraySize(decls_arr);
      FOR di := 0 TO m - 1 DO
        CheckDecl(cJSON_GetArrayItem(decls_arr, di));
      is_device_compiland := saved_device;
    END;
  END;
END;

PROCEDURE CheckRoot(root: ADRMEM);
BEGIN
  LoadDeviceExports(root);
  CheckLocalInterfaces(root);
  CheckLocalInterfaceUses(root, GetObj(root, 'local_interfaces'));
  MarkDeviceExports(root);
  CheckUnit(root);
END;

BEGIN
END.
