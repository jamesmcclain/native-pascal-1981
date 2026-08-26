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
  and the CINT/CCHAR/CSHORT/CLONG/CSIZE_T/CDOUBLE C-ABI width aliases (each
  resolved to the vintage type of matching flavor, since this v1 type-kind
  model doesn't track width), the wide INTEGER8/16/32/64, WORD8/16/32/64,
  and REAL32/64 extension names (same width-collapsing treatment), the
  local_interfaces a USES clause splices in (their TYPE/PROC/FUNC
  signatures are registered exactly like an EXTERN decl's), pointer
  arithmetic (POINTER +/- an ordinal offset) and dereference (`p^`), STRING/
  LSTRING character indexing (`s[i]`), the ORD/CHR/TRUNC/ROUND/SIZEOF/ODD/
  SUCC/PRED/ABS/SQR/SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT/HIBYTE/LOBYTE/WRD/
  WRD8/BYWORD builtins (checked against this file's own coarse tk model --
  e.g. WRD8 returns TK_WORD since there is no separate WORD8 tag here,
  unlike codegen.pas's own tid scheme; codegen.pas re-resolves every type
  itself by walking the AST directly rather than consuming this file's
  inferred tk annotations, so that coarseness only affects this file's own
  downstream error-checking precision, not the IR codegen.pas ultimately
  emits), and non-PROGRAM compilation units (MODULE/INTERFACE/
  IMPLEMENTATION, which put `decls` directly on the root instead of nesting
  under a `block` the way a PROGRAM does -- see CheckUnit). DEVICE MODULE
  checks, VARARGS attribute checks, and UNIT interface/implementation
  signature *matching* (validating IMPLEMENTATION bodies against their
  INTERFACE signatures) are still deferred; those aren't exercised by this
  repository's own native sources, which is what self-hosting requires.

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
  naming the literal's width/precision for codegen -- context_type's exact
  width (e.g. Integer32Type for a CINT target) when the surrounding context
  calls for one of the WORD/INTEGERn/REAL32 family, else the default
  IntegerType/RealType. Two known, functionally-harmless gaps remain
  against byte-identical parity with the Python reference (neither affects
  a single fixture in tests/fixtures/typecheck/, and neither changes
  codegen output, since the default IntegerType/RealType tag and no tag at
  all are handled identically by codegen):
    1. Because this v1 type-kind model collapses all integer widths into
       TK_INTEGER (and all WORD widths into TK_WORD), it always tags the
       default IntegerType/RealType regardless of a width-specific target
       context, rather than e.g. Integer32Type for a CINT-typed target.
    2. The Python reference itself does not tag perfectly consistently --
       e.g. a second `len := 0;` inside a nested IF's compound statement,
       assigning the exact same IntLiteral(0) to the exact same INTEGER
       variable as an earlier top-level `len := 0;` that DOES get tagged,
       is left untagged (verified against a minimal repro, not a
       self-hosting-only artifact). This stage tags every IntLiteral/
       RealLiteral node unconditionally instead, which is a strict, more
       internally-consistent superset of the Python reference's output
       rather than a divergent subset -- native never lacks a tag Python
       has, only (rarely) has one Python omits. }

(*$INCLUDE:'jsonutil.inc'*)
PROGRAM pascal1981_typecheck(input, output);

USES jsonutil;

FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_CreateObject: ADRMEM [C]; EXTERN;
FUNCTION cJSON_Print(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C]; EXTERN;
FUNCTION puts(str: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;

CONST
  TK_UNKNOWN  = 0;
  TK_INTEGER  = 1;
  TK_REAL     = 2;
  TK_BOOLEAN  = 3;
  TK_CHAR     = 4;
  TK_WORD     = 5;
  TK_STRING   = 6;
  TK_POINTER  = 7;
  TK_ARRAY    = 8;
  TK_RECORD   = 9;
  TK_VOID     = 10;
  TK_FILE     = 11; { aux holds the element TK (CHAR for a TEXT file);
    aux2 repurposed as a structure flag, 0 = BINARY (FILE OF T) / 1 = ASCII
    (the predeclared TEXT type), matching codegen.pas's own FILE
    representation so the two files agree on what "is a TEXT file"
    means. }
  TK_SET      = 12; { aux holds the base ordinal type's TK (TK_INTEGER,
    TK_CHAR, TK_WORD, or TK_BOOLEAN), mirroring codegen.pas's own SET
    representation, minus the exact lo/hi bounds this coarse v1 model
    doesn't need to track for element/IN/set-operator checking. }
  TK_ENUM     = 13; { a user-declared enumerated type. This coarse model
    doesn't distinguish one enum type from another (or from its members'
    constant symbols): every enum and enum constant carries TK_ENUM, the
    same deliberate looseness the rest of this file applies where a v1
    shape check is the documented scope. codegen.pas is the enforcement
    backstop, exactly as for the other coarse distinctions here. }

  MAX_SYMBOLS = 2000;
  MAX_TYPES   = 500;
  MAX_FIELDS  = 2000;
  MAX_ERRORS  = 200;
  MAX_PARAMS  = 16;
  MAX_EXPR_DEPTH = 64;
  MAX_STMT_DEPTH = 256;

TYPE
  SymRec = RECORD
    name: Str255;
    kind: Str255;       { 'VAR', 'CONST', 'TYPE', 'PROC', 'FUNC' }
    tk: INTEGER;
    aux: INTEGER;        { pointee/element TK, or record id }
    aux2: INTEGER;       { one level deeper: the pointee/element's OWN aux
                           (its record id, or its own element/pointee TK) --
                           carried so CheckDesignator can resolve a FIELD or
                           INDEX selector applied after a DEREF/INDEX, e.g.
                           `symbols[i].name` (array-of-record) or
                           `tok^.line` (pointer-to-record). Only one level
                           deep is tracked; a third level (e.g. a field of a
                           dereferenced element of an array of records)
                           isn't -- not needed by tests/fixtures/typecheck/
                           or this repository's own native sources. }
    idx_tk: INTEGER;     { array index TK }
    nparams: INTEGER;
    param_tk: ARRAY [1..MAX_PARAMS] OF INTEGER;
    ret_tk: INTEGER;
    is_vararg: BOOLEAN;  { TRUE for a routine carrying the [VARARGS]
                           attribute: its declared parameters are the FIXED
                           prefix and a call may pass extra trailing
                           arguments, which have no formal to check against
                           (C's own variadic tail -- see CheckFuncCall). }
    is_extern: BOOLEAN;  { TRUE for a routine declared EXTERN/EXTERNAL (or
                           [C]): its body lives in another compiland, so --
                           unlike a FORWARD -- a later body for the same name
                           in this same scope is an error, not a completion. }
  END;

  TypeRec = RECORD
    name: Str255;
    tk: INTEGER;
    aux: INTEGER;
    aux2: INTEGER;
    idx_tk: INTEGER;
  END;

  FieldRec = RECORD
    record_id: INTEGER;
    fname: Str255;
    ftk: INTEGER;
    faux: INTEGER;
    faux2: INTEGER;
  END;

VAR
  symbols: ARRAY [1..MAX_SYMBOLS] OF SymRec;
  nsymbols: INTEGER32;
  scope_stack: ARRAY [1..64] OF INTEGER32;
  scope_top: INTEGER;

  types: ARRAY [1..MAX_TYPES] OF TypeRec;
  ntypes: INTEGER32;

  fields: ARRAY [1..MAX_FIELDS] OF FieldRec;
  nfields: INTEGER32;
  next_record_id: INTEGER;

  last_designator_aux, last_designator_aux2: INTEGER; { side channel set by
    CheckDesignator on every call, mirroring codegen.pas's last_val_tk
    convention -- lets WithStmt recover the resolved record's id (aux) to
    scan `fields[]` for it, without changing CheckDesignator's signature or
    any existing call site. }

  errors: ARRAY [1..MAX_ERRORS] OF Str255;
  nerrors: INTEGER32;
  expr_depth, stmt_depth: INTEGER;

  cur_func_ret_tk: INTEGER; { TK_VOID when not inside a function }
  cur_func_aux, cur_func_aux2: INTEGER;
  cur_func_name: Str255;   { '' when not inside a function. `F := expr`
                             inside F's own body assigns through the
                             return-value slot (RETURN's target) rather than
                             any symbol-table entry -- mirrors
                             type_checker.py's stmts.py, which special-cases
                             `target_name == self.current_function.name`
                             instead of registering a shadow VAR. Not
                             shadowing is required for self-recursion: a
                             shadow VAR entry for the function's own name
                             would hide its FUNC entry from any recursive
                             call within its own body. }

{ ============================== utilities ============================== }
{ NodeType/GetObj/GetStr/GetInt/ReadAllStdin now live in jsonutil. }

PROCEDURE AddError(msg: Str255);
BEGIN
  IF nerrors < MAX_ERRORS THEN
  BEGIN
    nerrors := nerrors + 1;
    errors[nerrors] := msg;
  END;
END;

PROCEDURE AddError2(msg: Str255; name: Str255);
{ AddError with the offending identifier appended -- mirrors the codegen
  units' own AbortWith2. }
VAR
  buf: Str255;
BEGIN
  buf := msg;
  CONCAT(buf, name);
  AddError(buf);
END;

{ ============================ symbol table ============================= }

PROCEDURE PushScope;
BEGIN
  scope_top := scope_top + 1;
  scope_stack[scope_top] := nsymbols;
END;

PROCEDURE PopScope;
BEGIN
  nsymbols := scope_stack[scope_top];
  scope_top := scope_top - 1;
END;

FUNCTION LookupSymbol(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := nsymbols;
  WHILE (i >= 1) AND THEN (symbols[i].name <> name) DO
    i := i - 1;
  LookupSymbol := i;
END;

FUNCTION LookupSymbolInScope(name: Str255): INTEGER32;
{ LookupSymbol above searches every live scope, answering "is this name
  visible". This one stops at the current scope's low-water mark, answering
  "was this name already declared *here*" -- the question a redeclaration
  rule has to ask, since shadowing an outer declaration is not one. Returns 0
  when the name was not declared in this scope. }
VAR
  i, base: INTEGER32;
BEGIN
  IF scope_top = 0 THEN base := 0
  ELSE base := scope_stack[scope_top];
  i := nsymbols;
  WHILE (i > base) AND THEN (symbols[i].name <> name) DO
    i := i - 1;
  IF i > base THEN LookupSymbolInScope := i
  ELSE LookupSymbolInScope := 0;
END;

FUNCTION DefineSymbol(name: Str255; kind: Str255; tk, aux, aux2, idx_tk: INTEGER): INTEGER32;
BEGIN
  nsymbols := nsymbols + 1;
  symbols[nsymbols].name := name;
  symbols[nsymbols].kind := kind;
  symbols[nsymbols].tk := tk;
  symbols[nsymbols].aux := aux;
  symbols[nsymbols].aux2 := aux2;
  symbols[nsymbols].idx_tk := idx_tk;
  symbols[nsymbols].nparams := 0;
  symbols[nsymbols].ret_tk := TK_VOID;
  symbols[nsymbols].is_vararg := FALSE;
  symbols[nsymbols].is_extern := FALSE;
  DefineSymbol := nsymbols;
END;

FUNCTION LookupType(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := ntypes;
  WHILE (i >= 1) AND THEN (types[i].name <> name) DO
    i := i - 1;
  LookupType := i;
END;

PROCEDURE AddFieldEntry(record_id: INTEGER; fname: Str255; ftk, faux, faux2: INTEGER);
BEGIN
  IF nfields < MAX_FIELDS THEN
  BEGIN
    nfields := nfields + 1;
    fields[nfields].record_id := record_id;
    fields[nfields].fname := fname;
    fields[nfields].ftk := ftk;
    fields[nfields].faux := faux;
    fields[nfields].faux2 := faux2;
  END;
END;

FUNCTION LookupField(record_id: INTEGER; fname: Str255): INTEGER32;
VAR
  i: INTEGER32;
BEGIN
  i := nfields;
  WHILE (i >= 1) AND THEN ((fields[i].record_id <> record_id) OR (fields[i].fname <> fname)) DO
    i := i - 1;
  LookupField := i;
END;

PROCEDURE AddUniqueRecordField(record_id: INTEGER; fname: Str255; ftk, faux, faux2: INTEGER);
BEGIN
  IF LookupField(record_id, fname) <> 0 THEN
    AddError('Duplicate record field name')
  ELSE
    AddFieldEntry(record_id, fname, ftk, faux, faux2);
END;

FUNCTION IsOrdinal(tk: INTEGER): BOOLEAN;
BEGIN
  IsOrdinal := (tk = TK_INTEGER) OR (tk = TK_WORD) OR (tk = TK_CHAR) OR (tk = TK_BOOLEAN) OR (tk = TK_ENUM);
END;

FUNCTION IsNumeric(tk: INTEGER): BOOLEAN;
BEGIN
  IsNumeric := (tk = TK_INTEGER) OR (tk = TK_REAL) OR (tk = TK_WORD);
END;

{ ========================== type-expr resolution ======================= }

PROCEDURE ResolveTypeExpr(node: ADRMEM; VAR tk, aux, aux2, idx_tk: INTEGER);
VAR
  nt, name: Str255;
  base_node, elem_node, fields_arr, tup, items, names_arr, ftype_node: ADRMEM;
  variants_arr, arm_node, tag_type_node: ADRMEM;
  inner_tk, inner_aux, inner_aux2, inner_idx: INTEGER;
  ti: INTEGER32;
  rid: INTEGER;
  n, fi, nn, ni: INTEGER32;
  nm: Str255;
BEGIN
  tk := TK_UNKNOWN;
  aux := 0;
  aux2 := 0;
  idx_tk := 0;
  nt := NodeType(node);
  IF nt = 'NamedType' THEN
  BEGIN
    name := GetStr(node, 'name');
    IF name = 'INTEGER' THEN tk := TK_INTEGER
    ELSE IF name = 'WORD' THEN tk := TK_WORD
    ELSE IF name = 'REAL' THEN tk := TK_REAL
    ELSE IF name = 'BOOLEAN' THEN tk := TK_BOOLEAN
    ELSE IF name = 'CHAR' THEN tk := TK_CHAR
    ELSE IF name = 'STRING' THEN tk := TK_STRING
    ELSE IF name = 'LSTRING' THEN tk := TK_STRING
    { Wide-integer/real extension names (feature-gated under the extended
      dialect): this v1 type-kind model doesn't track width, so each just
      aliases to its base kind -- matching how INTEGER32/WORD32/etc. behave
      identically to INTEGER/WORD for every check this stage performs. }
    ELSE IF (name = 'INTEGER8') OR (name = 'INTEGER16') OR (name = 'INTEGER32') OR (name = 'INTEGER64') THEN tk := TK_INTEGER
    ELSE IF (name = 'WORD8') OR (name = 'WORD16') OR (name = 'WORD32') OR (name = 'WORD64') THEN tk := TK_WORD
    ELSE IF (name = 'REAL32') OR (name = 'REAL64') THEN tk := TK_REAL
    { ADRMEM/ADSMEM (and the CPTR C-ABI alias) are address types -- codegen's
      opaque-pointer model treats them as "pointer to CHAR" (see
      types_resolve.py's resolve_type: ADRMEM -> PointerType(CHAR_TYPE)). }
    ELSE IF (name = 'ADRMEM') OR (name = 'ADSMEM') OR (name = 'CPTR') THEN
    BEGIN
      tk := TK_POINTER;
      aux := TK_CHAR;
    END
    { C-ABI fixed-width scalar aliases (builtins_registry.py's
      C_ABI_TYPE_ALIASES): each resolves to the vintage type of matching
      flavor, since this stage doesn't distinguish integer/real width. }
    ELSE IF name = 'CCHAR' THEN tk := TK_CHAR
    ELSE IF (name = 'CSHORT') OR (name = 'CINT') OR (name = 'CLONG') OR (name = 'CSIZE_T') THEN tk := TK_INTEGER
    ELSE IF name = 'CDOUBLE' THEN tk := TK_REAL
    ELSE IF name = 'TEXT' THEN
    BEGIN
      tk := TK_FILE;
      aux := TK_CHAR;
      aux2 := 1; { ASCII/TEXT structure }
    END
    ELSE BEGIN
      ti := LookupType(name);
      IF ti = 0 THEN
      BEGIN
        AddError('Unknown type name');
        tk := TK_UNKNOWN;
      END
      ELSE BEGIN
        tk := types[ti].tk;
        aux := types[ti].aux;
        aux2 := types[ti].aux2;
        idx_tk := types[ti].idx_tk;
      END;
    END;
  END
  ELSE IF nt = 'LStringType' THEN
    tk := TK_STRING
  ELSE IF nt = 'PointerType' THEN
  BEGIN
    base_node := GetObj(node, 'base');
    ResolveTypeExpr(base_node, inner_tk, inner_aux, inner_aux2, inner_idx);
    tk := TK_POINTER;
    aux := inner_tk;
    aux2 := inner_aux;
  END
  ELSE IF nt = 'FileType' THEN
  BEGIN
    elem_node := GetObj(node, 'element_type');
    ResolveTypeExpr(elem_node, inner_tk, inner_aux, inner_aux2, inner_idx);
    tk := TK_FILE;
    aux := inner_tk;
    IF GetStr(node, 'structure') = 'ASCII' THEN aux2 := 1 ELSE aux2 := 0;
  END
  ELSE IF nt = 'ArrayType' THEN
  BEGIN
    elem_node := GetObj(node, 'element_type');
    ResolveTypeExpr(elem_node, inner_tk, inner_aux, inner_aux2, inner_idx);
    tk := TK_ARRAY;
    aux := inner_tk;
    aux2 := inner_aux;
    idx_tk := TK_INTEGER;
  END
  ELSE IF nt = 'RecordType' THEN
  BEGIN
    rid := next_record_id;
    next_record_id := next_record_id + 1;
    fields_arr := GetObj(node, 'fields');
    n := cJSON_GetArraySize(fields_arr);
    FOR fi := 0 TO n - 1 DO
    BEGIN
      tup := cJSON_GetArrayItem(fields_arr, fi);
      items := GetObj(tup, 'items');
      names_arr := cJSON_GetArrayItem(items, 0);
      ftype_node := cJSON_GetArrayItem(items, 1);
      ResolveTypeExpr(ftype_node, inner_tk, inner_aux, inner_aux2, inner_idx);
      nn := cJSON_GetArraySize(names_arr);
      FOR ni := 0 TO nn - 1 DO
      BEGIN
        nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, ni)));
        AddUniqueRecordField(rid, nm, inner_tk, inner_aux, inner_aux2);
      END;
    END;
    variants_arr := GetObj(node, 'variants');
    IF cJSON_GetArraySize(variants_arr) > 0 THEN
    BEGIN
      tag_type_node := GetObj(node, 'tag_type');
      ResolveTypeExpr(tag_type_node, inner_tk, inner_aux, inner_aux2, inner_idx);
      IF NOT IsOrdinal(inner_tk) THEN
        AddError('Variant record tag type must be ordinal');
      IF GetBool(node, 'has_tag') THEN
      BEGIN
        nm := GetStr(node, 'tag_name');
        AddUniqueRecordField(rid, nm, inner_tk, inner_aux, inner_aux2);
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
          ResolveTypeExpr(ftype_node, inner_tk, inner_aux, inner_aux2, inner_idx);
          nn := cJSON_GetArraySize(names_arr);
          FOR n := 0 TO nn - 1 DO
          BEGIN
            nm := CStrToStr255(cJSON_GetStringValue(cJSON_GetArrayItem(names_arr, n)));
            AddUniqueRecordField(rid, nm, inner_tk, inner_aux, inner_aux2);
          END;
        END;
      END;
    END;
    tk := TK_RECORD;
    aux := rid;
  END
  ELSE IF (nt = 'SubrangeType') OR (nt = 'BuiltinType') THEN
  BEGIN
    { Only reachable today from a SetType's `base` field (ParseSetBase's own
      output shapes) -- SubrangeType elsewhere (e.g. an ARRAY index range)
      is read directly by its own caller, not through ResolveTypeExpr. A
      SubrangeType base's ordinal kind follows its low bound's literal kind
      (CharLiteral -> TK_CHAR, BoolLiteral -> TK_BOOLEAN, else TK_INTEGER);
      a BuiltinType base is a reserved-word ordinal type name. }
    IF nt = 'SubrangeType' THEN
    BEGIN
      IF NodeType(GetObj(node, 'low')) = 'CharLiteral' THEN tk := TK_CHAR
      ELSE IF NodeType(GetObj(node, 'low')) = 'BoolLiteral' THEN tk := TK_BOOLEAN
      ELSE tk := TK_INTEGER;
    END
    ELSE BEGIN
      name := GetStr(node, 'name');
      IF name = 'CHAR' THEN tk := TK_CHAR
      ELSE IF name = 'BOOLEAN' THEN tk := TK_BOOLEAN
      ELSE IF name = 'WORD' THEN tk := TK_WORD
      ELSE IF name = 'INTEGER' THEN tk := TK_INTEGER
      ELSE BEGIN
        AddError('SET OF <base> requires an ordinal base type');
        tk := TK_UNKNOWN;
      END;
    END;
  END
  ELSE IF nt = 'EnumType' THEN
    tk := TK_ENUM
  ELSE IF nt = 'SetType' THEN
  BEGIN
    base_node := GetObj(node, 'base');
    ResolveTypeExpr(base_node, inner_tk, inner_aux, inner_aux2, inner_idx);
    IF NOT IsOrdinal(inner_tk) THEN
      AddError('SET OF <base> requires an ordinal base type');
    tk := TK_SET;
    aux := inner_tk;
  END;
END;

{ ============================ forward decls ============================ }

FUNCTION CheckExpr(node: ADRMEM): INTEGER; FORWARD;
PROCEDURE CheckStmt(node: ADRMEM); FORWARD;
FUNCTION IsForeignRoutineDecl(decl: ADRMEM): BOOLEAN; FORWARD;

{ =============================== expressions ============================ }

PROCEDURE TagResolvedType(node: ADRMEM; type_name: Str255);
VAR
  tobj: ADRMEM;
BEGIN
  tobj := cJSON_CreateObject;
  AddStringField(tobj, '__type_system__', type_name);
  AddField(node, 'resolved_type', tobj);
END;

FUNCTION CanAssign(target_tk, expr_tk: INTEGER): BOOLEAN;
BEGIN
  IF (target_tk = TK_UNKNOWN) OR (expr_tk = TK_UNKNOWN) THEN
    CanAssign := TRUE
  ELSE IF target_tk = expr_tk THEN
    CanAssign := TRUE
  ELSE IF (target_tk = TK_REAL) AND (expr_tk = TK_INTEGER) THEN
    CanAssign := TRUE
  ELSE IF (target_tk = TK_WORD) AND (expr_tk = TK_INTEGER) THEN
    { The vintage "INTEGER constant changes to WORD" rule (manual). The
      Python reference only allows this for a *constant* INTEGER
      expression; this file, like codegen.pas's own TypesCompatibleForAssign,
      simplifies by allowing it for any INTEGER-typed expression, not just
      literals -- a documented, deliberate looseness, not an oversight. }
    CanAssign := TRUE
  ELSE IF (target_tk = TK_POINTER) AND (expr_tk = TK_POINTER) THEN
    CanAssign := TRUE
  ELSE
    CanAssign := FALSE;
END;

FUNCTION CheckDesignator(node: ADRMEM): INTEGER;
{ Walks the base identifier's selectors, threading a (tk, aux, aux2) triple
  along so a FIELD or INDEX selector applied right after a DEREF/INDEX can
  still resolve (aux2 carries the element/pointee's own aux -- see SymRec's
  aux2 doc comment). Only one level of nesting is tracked this way. }
VAR
  name: Str255;
  si: INTEGER32;
  sel_arr: ADRMEM;
  nsel, i: INTEGER32;
  sel, idx_expr: ADRMEM;
  skind, fname: Str255;
  tk, aux, aux2, itk, new_tk, new_aux: INTEGER;
  fi: INTEGER32;
BEGIN
  name := GetStr(node, 'name');
  si := LookupSymbol(name);
  IF si = 0 THEN
  BEGIN
    AddError('Undefined identifier');
    CheckDesignator := TK_UNKNOWN;
    RETURN;
  END;
  tk := symbols[si].tk;
  aux := symbols[si].aux;
  aux2 := symbols[si].aux2;
  sel_arr := GetObj(node, 'selectors');
  nsel := cJSON_GetArraySize(sel_arr);
  FOR i := 0 TO nsel - 1 DO
  BEGIN
    sel := cJSON_GetArrayItem(sel_arr, i);
    skind := GetStr(sel, 'kind');
    IF skind = 'FIELD' THEN
    BEGIN
      IF tk <> TK_RECORD THEN
      BEGIN
        AddError('Field selector on non-record value');
        tk := TK_UNKNOWN;
        aux := 0;
        aux2 := 0;
      END
      ELSE BEGIN
        fname := CStrToStr255(cJSON_GetStringValue(GetObj(sel, 'index_or_field')));
        fi := LookupField(aux, fname);
        IF fi = 0 THEN
        BEGIN
          AddError('Unknown field');
          tk := TK_UNKNOWN;
          aux := 0;
          aux2 := 0;
        END
        ELSE BEGIN
          tk := fields[fi].ftk;
          aux := fields[fi].faux;
          aux2 := fields[fi].faux2;
        END;
      END;
    END
    ELSE IF skind = 'INDEX' THEN
    BEGIN
      IF tk = TK_STRING THEN
      BEGIN
        { s[i] on a STRING/LSTRING indexes its characters (Str255[0] is the
          length byte, matching this repository's own Str255 usage) --
          not array indexing, so there's no per-declaration element/aux to
          carry forward; the result is always a plain CHAR. }
        idx_expr := GetObj(sel, 'index_or_field');
        itk := CheckExpr(idx_expr);
        IF NOT IsOrdinal(itk) AND (itk <> TK_UNKNOWN) THEN
          AddError('String index must be an ordinal type');
        tk := TK_CHAR;
        aux := 0;
        aux2 := 0;
      END
      ELSE IF tk <> TK_ARRAY THEN
      BEGIN
        AddError('Index selector on non-array value');
        tk := TK_UNKNOWN;
        aux := 0;
        aux2 := 0;
      END
      ELSE BEGIN
        idx_expr := GetObj(sel, 'index_or_field');
        itk := CheckExpr(idx_expr);
        IF NOT IsOrdinal(itk) AND (itk <> TK_UNKNOWN) THEN
          AddError('Array index must be an ordinal type');
        new_tk := aux;
        new_aux := aux2;
        tk := new_tk;
        aux := new_aux;
        aux2 := 0;
      END;
    END
    ELSE IF skind = 'DEREF' THEN
    BEGIN
      IF tk = TK_FILE THEN
      BEGIN
        { F^: the file's buffer variable (the standard READ/WRITE-underlying
          "current component" model, manual ch.13) -- its type is the file's
          own element type, carried in aux exactly like a POINTER's pointee. }
        new_tk := aux;
        tk := new_tk;
        aux := 0;
        aux2 := 0;
      END
      ELSE IF tk <> TK_POINTER THEN
      BEGIN
        AddError('Dereference of non-pointer value');
        tk := TK_UNKNOWN;
        aux := 0;
        aux2 := 0;
      END
      ELSE BEGIN
        new_tk := aux;
        new_aux := aux2;
        tk := new_tk;
        aux := new_aux;
        aux2 := 0;
      END;
    END;
  END;
  last_designator_aux := aux;
  last_designator_aux2 := aux2;
  CheckDesignator := tk;
END;

FUNCTION CheckFuncCall(node: ADRMEM): INTEGER;
VAR
  name: Str255;
  args_arr, warg: ADRMEM;
  nargs, i, si: INTEGER32;
  atk: INTEGER;
BEGIN
  name := GetStr(node, 'name');
  args_arr := GetObj(node, 'args');
  nargs := cJSON_GetArraySize(args_arr);
  IF name = 'WRD' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('WRD requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('WRD argument must be an ordinal type');
    END;
    CheckFuncCall := TK_WORD;
    RETURN;
  END;
  IF name = 'BYWORD' THEN
  BEGIN
    IF nargs <> 2 THEN
      AddError('BYWORD requires exactly two arguments')
    ELSE
      FOR i := 0 TO nargs - 1 DO
      BEGIN
        atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
        IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
          AddError('BYWORD argument must be an ordinal type');
      END;
    CheckFuncCall := TK_WORD;
    RETURN;
  END;
  IF name = 'ORD' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('ORD requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('ORD argument must be an ordinal type');
    END;
    CheckFuncCall := TK_INTEGER;
    RETURN;
  END;
  IF name = 'CHR' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('CHR requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT CanAssign(TK_INTEGER, atk) THEN
        AddError('CHR argument must be INTEGER');
    END;
    CheckFuncCall := TK_CHAR;
    RETURN;
  END;
  IF (name = 'TRUNC') OR (name = 'ROUND') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('TRUNC/ROUND requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_REAL) AND (atk <> TK_UNKNOWN) THEN
        AddError('TRUNC/ROUND argument must be REAL');
    END;
    CheckFuncCall := TK_INTEGER;
    RETURN;
  END;
  IF name = 'ODD' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('ODD requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_UNKNOWN) THEN
        AddError('ODD argument must be INTEGER or WORD');
    END;
    CheckFuncCall := TK_BOOLEAN;
    RETURN;
  END;
  IF (name = 'SUCC') OR (name = 'PRED') THEN
  BEGIN
    IF nargs <> 1 THEN
    BEGIN
      AddError('SUCC/PRED requires exactly one argument');
      CheckFuncCall := TK_UNKNOWN;
    END
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_CHAR) AND (atk <> TK_ENUM) AND (atk <> TK_UNKNOWN) THEN
        AddError('SUCC/PRED argument must be INTEGER, WORD, CHAR, or an enumerated type');
      CheckFuncCall := atk;
    END;
    RETURN;
  END;
  IF (name = 'ABS') OR (name = 'SQR') THEN
  BEGIN
    IF nargs <> 1 THEN
    BEGIN
      AddError('ABS/SQR requires exactly one argument');
      CheckFuncCall := TK_UNKNOWN;
    END
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_REAL) AND (atk <> TK_UNKNOWN) THEN
        AddError('ABS/SQR argument must be INTEGER, WORD, or REAL');
      CheckFuncCall := atk;
    END;
    RETURN;
  END;
  IF (name = 'SQRT') OR (name = 'SIN') OR (name = 'COS') OR (name = 'LN') OR
     (name = 'EXP') OR (name = 'ARCTAN') OR (name = 'FLOAT') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_REAL) AND (atk <> TK_UNKNOWN) THEN
        AddError('SQRT/SIN/COS/LN/EXP/ARCTAN/FLOAT argument must be INTEGER, WORD, or REAL');
    END;
    CheckFuncCall := TK_REAL;
    RETURN;
  END;
  IF (name = 'HIBYTE') OR (name = 'LOBYTE') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('HIBYTE/LOBYTE requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_UNKNOWN) THEN
        AddError('HIBYTE/LOBYTE argument must be INTEGER or WORD');
    END;
    CheckFuncCall := TK_CHAR;
    RETURN;
  END;
  IF name = 'WRD8' THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('WRD8 requires exactly one argument')
    ELSE BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, 0));
      IF NOT IsOrdinal(atk) AND (atk <> TK_UNKNOWN) THEN
        AddError('WRD8 argument must be an ordinal type');
    END;
    { typechecker.pas's coarse type model has no distinct WORD8 tag (see
      the header comment); codegen.pas resolves the real result type
      independently by re-walking the AST itself, so this tag is only
      used for this file's own downstream error-checking, same as WRD
      returning TK_WORD above. }
    CheckFuncCall := TK_WORD;
    RETURN;
  END;
  IF (name = 'EOF') OR (name = 'EOLN') THEN
  BEGIN
    IF nargs <> 1 THEN
      AddError('EOF/EOLN requires exactly one argument')
    ELSE BEGIN
      warg := cJSON_GetArrayItem(args_arr, 0);
      IF NodeType(warg) <> 'Identifier' THEN
        AddError('EOF/EOLN argument must be a file variable')
      ELSE BEGIN
        si := LookupSymbol(GetStr(warg, 'name'));
        IF si = 0 THEN
          AddError('Undefined identifier')
        ELSE IF symbols[si].tk <> TK_FILE THEN
          AddError('EOF/EOLN argument must be a file variable')
        ELSE IF (name = 'EOLN') AND ((symbols[si].aux <> TK_CHAR) OR (symbols[si].aux2 <> 1)) THEN
          AddError('EOLN requires a TEXT file, not a binary FILE');
      END;
    END;
    CheckFuncCall := TK_BOOLEAN;
    RETURN;
  END;
  si := LookupSymbol(name);
  IF si = 0 THEN
  BEGIN
    AddError('Undefined function');
    FOR i := 0 TO nargs - 1 DO
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
    CheckFuncCall := TK_UNKNOWN;
    RETURN;
  END;
  { A [VARARGS] routine's declared parameters are only the fixed prefix, so
    MORE actuals than formals is legal there (and only there); every tail
    argument still has to be a well-formed expression, but has no formal to
    be assignment-compatible with. }
  IF (nargs <> symbols[si].nparams)
     AND NOT (symbols[si].is_vararg AND (nargs > symbols[si].nparams)) THEN
    AddError('Argument count mismatch')
  ELSE
    FOR i := 0 TO nargs - 1 DO
    BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
      IF i < symbols[si].nparams THEN
        IF NOT CanAssign(symbols[si].param_tk[i + 1], atk) THEN
          AddError('Argument type mismatch');
    END;
  CheckFuncCall := symbols[si].ret_tk;
END;

FUNCTION CheckExpr(node: ADRMEM): INTEGER;
VAR
  nt, name: Str255;
  si: INTEGER32;
  left_node, right_node, operand_node, type_node: ADRMEM;
  lt, rt, ot, op_kind, aux, aux2, idx_tk: INTEGER;
  op: Str255;
  elems_arr, elem_node: ADRMEM;
  n_elems, ei: INTEGER32;
BEGIN
  expr_depth := expr_depth + 1;
  IF expr_depth > MAX_EXPR_DEPTH THEN
  BEGIN
    AddError('expression too complex (nesting deeper than 64); try breaking it up with intermediate value assigns');
    CheckExpr := TK_UNKNOWN;
  END
  ELSE BEGIN
  nt := NodeType(node);
  IF nt = 'IntLiteral' THEN
  BEGIN
    TagResolvedType(node, 'IntegerType');
    CheckExpr := TK_INTEGER;
  END
  ELSE IF nt = 'RealLiteral' THEN
  BEGIN
    TagResolvedType(node, 'RealType');
    CheckExpr := TK_REAL;
  END
  ELSE IF nt = 'BoolLiteral' THEN CheckExpr := TK_BOOLEAN
  ELSE IF nt = 'CharLiteral' THEN CheckExpr := TK_CHAR
  ELSE IF nt = 'StringLiteral' THEN CheckExpr := TK_STRING
  ELSE IF nt = 'NilLiteral' THEN CheckExpr := TK_POINTER
  ELSE IF nt = 'SizeofExpr' THEN CheckExpr := TK_INTEGER
  ELSE IF nt = 'AdrExpr' THEN
  BEGIN
    { ADR <var>: address-of a bare variable. This stage's type model has no
      distinct ADRMEM tag or per-declaration pointer flavor/space (unlike
      codegen.pas's own richer table) -- TK_POINTER is the same coarse tag
      NilLiteral above already uses for every other pointer-shaped result. }
    si := LookupSymbol(GetStr(node, 'name'));
    IF si = 0 THEN
    BEGIN
      AddError('Undefined identifier');
      CheckExpr := TK_UNKNOWN;
    END
    ELSE
      CheckExpr := TK_POINTER;
  END
  ELSE IF nt = 'Identifier' THEN
  BEGIN
    name := GetStr(node, 'name');
    si := LookupSymbol(name);
    IF si = 0 THEN
    BEGIN
      AddError('Undefined identifier');
      CheckExpr := TK_UNKNOWN;
    END
    ELSE
      CheckExpr := symbols[si].tk;
  END
  ELSE IF nt = 'SetConstructor' THEN
  BEGIN
    { Element/range-bound ordinal checking only; this v1 type-kind model has
      no way to carry a SET's declared base ordinal kind through CheckExpr's
      bare-tk return value (unlike codegen.pas's richer type table), so a
      mismatched base across elements (e.g. mixing CHAR and INTEGER) is not
      caught here -- codegen.pas is the enforcement backstop for that, same
      division of labor as elsewhere in this file (see the header comment). }
    elems_arr := GetObj(node, 'elements');
    n_elems := cJSON_GetArraySize(elems_arr);
    FOR ei := 0 TO n_elems - 1 DO
    BEGIN
      elem_node := cJSON_GetArrayItem(elems_arr, ei);
      IF NodeType(elem_node) = 'RangeExpr' THEN
      BEGIN
        lt := CheckExpr(GetObj(elem_node, 'low'));
        rt := CheckExpr(GetObj(elem_node, 'high'));
        IF (lt <> TK_UNKNOWN) AND NOT IsOrdinal(lt) THEN
          AddError('Set range bound must be an ordinal type');
        IF (rt <> TK_UNKNOWN) AND NOT IsOrdinal(rt) THEN
          AddError('Set range bound must be an ordinal type');
      END
      ELSE BEGIN
        ot := CheckExpr(elem_node);
        IF (ot <> TK_UNKNOWN) AND NOT IsOrdinal(ot) THEN
          AddError('Set element must be an ordinal type');
      END;
    END;
    CheckExpr := TK_SET;
  END
  ELSE IF nt = 'Designator' THEN
    CheckExpr := CheckDesignator(node)
  ELSE IF nt = 'FuncCall' THEN
    CheckExpr := CheckFuncCall(node)
  ELSE IF nt = 'RetypeExpr' THEN
  BEGIN
    { RETYPE(TypeName, expr) is a language construct, not a function call.
      Resolve its target through the normal NamedType path and still check
      the source expression. }
    ot := CheckExpr(GetObj(node, 'expr'));
    type_node := CreateNode('NamedType');
    AddStringField(type_node, 'name', GetStr(node, 'type_id'));
    ResolveTypeExpr(type_node, lt, aux, aux2, idx_tk);
    CheckExpr := lt;
  END
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    left_node := GetObj(node, 'left');
    right_node := GetObj(node, 'right');
    lt := CheckExpr(left_node);
    rt := CheckExpr(right_node);
    op := GetStr(node, 'op');
    IF (lt = TK_UNKNOWN) OR (rt = TK_UNKNOWN) THEN
      CheckExpr := TK_UNKNOWN
    ELSE IF (op = 'AND') OR (op = 'OR') OR (op = 'AND_THEN') OR (op = 'OR_ELSE') THEN
    BEGIN
      IF (lt <> TK_BOOLEAN) OR (rt <> TK_BOOLEAN) THEN
      BEGIN
        AddError('Boolean operator requires BOOLEAN operands');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE
        CheckExpr := TK_BOOLEAN;
    END
    ELSE IF (op = 'EQ') OR (op = 'NEQ') OR (op = 'LT') OR (op = 'LE') OR (op = 'GT') OR (op = 'GE') THEN
    BEGIN
      IF NOT (IsNumeric(lt) AND IsNumeric(rt)) AND (lt <> rt) THEN
        AddError('Comparison operands are not comparable');
      CheckExpr := TK_BOOLEAN;
    END
    ELSE IF op = 'IN' THEN
    BEGIN
      IF NOT IsOrdinal(lt) THEN
        AddError('IN requires an ordinal left operand');
      IF rt <> TK_SET THEN
        AddError('IN requires a SET right operand');
      CheckExpr := TK_BOOLEAN;
    END
    ELSE IF (lt = TK_SET) OR (rt = TK_SET) THEN
    BEGIN
      { Set union/intersection/difference (PLUS/MINUS/MUL): both operands
        must be SET. Base-kind mismatch (e.g. SET OF CHAR + SET OF INTEGER)
        is not caught here -- see the SetConstructor case's comment on why
        this coarse model can't carry a SET's base ordinal kind. }
      IF (lt <> TK_SET) OR (rt <> TK_SET) THEN
      BEGIN
        AddError('Set operator requires SET operands');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE IF (op = 'PLUS') OR (op = 'MINUS') OR (op = 'MUL') THEN
        CheckExpr := TK_SET
      ELSE
      BEGIN
        AddError('Unsupported SET operator');
        CheckExpr := TK_UNKNOWN;
      END;
    END
    ELSE BEGIN
      { arithmetic: PLUS/MINUS/TIMES/DIVIDE/DIV/MOD. Pointer arithmetic
        (pointer +/- an ordinal offset, e.g. `src_buf + pos`) is a real
        pattern in this repository's own native sources' hand-rolled
        growable buffers, so a POINTER operand paired with a numeric one
        stays a POINTER rather than tripping the numeric-operands error. }
      IF (lt = TK_POINTER) AND IsNumeric(rt) THEN
        CheckExpr := TK_POINTER
      ELSE IF (rt = TK_POINTER) AND IsNumeric(lt) THEN
        CheckExpr := TK_POINTER
      ELSE IF NOT (IsNumeric(lt) AND IsNumeric(rt)) THEN
      BEGIN
        AddError('Arithmetic operator requires numeric operands');
        CheckExpr := TK_UNKNOWN;
      END
      ELSE IF (lt = TK_REAL) OR (rt = TK_REAL) THEN
        CheckExpr := TK_REAL
      ELSE
        CheckExpr := TK_INTEGER;
    END;
  END
  ELSE IF nt = 'UnaryOp' THEN
  BEGIN
    operand_node := GetObj(node, 'operand');
    ot := CheckExpr(operand_node);
    op := GetStr(node, 'op');
    IF op = 'NOT' THEN
    BEGIN
      IF (ot <> TK_BOOLEAN) AND (ot <> TK_UNKNOWN) THEN
        AddError('NOT requires a BOOLEAN operand');
      CheckExpr := TK_BOOLEAN;
    END
    ELSE BEGIN
      IF ((op = 'PLUS') OR (op = 'MINUS')) AND (NodeType(operand_node) = 'IntLiteral') THEN
        TagResolvedType(node, 'IntegerType');
      CheckExpr := ot;
    END;
  END
  ELSE
    CheckExpr := TK_UNKNOWN;
  END;
  expr_depth := expr_depth - 1;
END;

{ =============================== statements ============================= }

PROCEDURE CheckCompoundOrStmt(node: ADRMEM);
VAR
  nt: Str255;
  stmts_arr: ADRMEM;
  n, i: INTEGER32;
BEGIN
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    IF nt = 'CompoundStmt' THEN
    BEGIN
      stmts_arr := GetObj(node, 'stmts');
      n := cJSON_GetArraySize(stmts_arr);
      FOR i := 0 TO n - 1 DO
        CheckStmt(cJSON_GetArrayItem(stmts_arr, i));
    END
    ELSE
      CheckStmt(node);
  END;
END;

PROCEDURE CheckStmtList(arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  n := cJSON_GetArraySize(arr);
  FOR i := 0 TO n - 1 DO
    CheckStmt(cJSON_GetArrayItem(arr, i));
END;

PROCEDURE CheckStmt(node: ADRMEM);
VAR
  nt, varname: Str255;
  target_node, expr_node, cond_node, args_arr, warg, wexpr: ADRMEM;
  target_tk, expr_tk, cond_tk, vi: INTEGER;
  si: INTEGER32;
  nargs, i, start_arg: INTEGER32;
  pname: Str255;
  with_targets, with_target: ADRMEM;
  n_with_targets, wi, fi, pushed: INTEGER32;
  with_tk, rec_id: INTEGER;
BEGIN
  stmt_depth := stmt_depth + 1;
  IF stmt_depth > MAX_STMT_DEPTH THEN
    AddError('statements nested too deeply (deeper than 256); try splitting the routine up')
  ELSE BEGIN
  IF node = NIL THEN
    nt := ''
  ELSE
    nt := NodeType(node);
  IF nt = 'AssignStmt' THEN
  BEGIN
    target_node := GetObj(node, 'target');
    expr_node := GetObj(node, 'expr');
    varname := GetStr(target_node, 'name');
    IF (cur_func_name <> '') AND (varname = cur_func_name) AND
       (cJSON_GetArraySize(GetObj(target_node, 'selectors')) = 0) THEN
    BEGIN
      { `F := expr` inside F's own body assigns through the return-value
        slot, not any symbol-table entry (see cur_func_name's doc comment
        -- this must NOT fall through to CheckDesignator, which would
        either miss it (no such VAR symbol) or, worse, collide with a
        same-named callable symbol). }
      target_tk := cur_func_ret_tk;
    END
    ELSE
      target_tk := CheckDesignator(target_node);
    expr_tk := CheckExpr(expr_node);
    IF NOT CanAssign(target_tk, expr_tk) THEN
      AddError('Cannot assign incompatible type');
  END
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    cond_tk := CheckExpr(GetObj(node, 'cond'));
    IF (cond_tk <> TK_BOOLEAN) AND (cond_tk <> TK_UNKNOWN) THEN
      AddError('IF condition must be BOOLEAN');
    CheckCompoundOrStmt(GetObj(node, 'then_branch'));
    CheckCompoundOrStmt(GetObj(node, 'else_branch'));
  END
  ELSE IF nt = 'WhileStmt' THEN
  BEGIN
    cond_tk := CheckExpr(GetObj(node, 'cond'));
    IF (cond_tk <> TK_BOOLEAN) AND (cond_tk <> TK_UNKNOWN) THEN
      AddError('WHILE condition must be BOOLEAN');
    CheckCompoundOrStmt(GetObj(node, 'body'));
  END
  ELSE IF nt = 'RepeatStmt' THEN
  BEGIN
    cond_tk := CheckExpr(GetObj(node, 'cond'));
    IF (cond_tk <> TK_BOOLEAN) AND (cond_tk <> TK_UNKNOWN) THEN
      AddError('REPEAT UNTIL condition must be BOOLEAN');
    CheckStmtList(GetObj(node, 'body'));
  END
  ELSE IF nt = 'ForStmt' THEN
  BEGIN
    varname := GetStr(node, 'var');
    si := LookupSymbol(varname);
    IF si = 0 THEN
      AddError('Undefined identifier')
    ELSE BEGIN
      vi := symbols[si].tk;
      IF NOT IsOrdinal(vi) THEN
        AddError('FOR loop variable must be an ordinal type');
    END;
    cond_tk := CheckExpr(GetObj(node, 'start'));
    cond_tk := CheckExpr(GetObj(node, 'end'));
    CheckCompoundOrStmt(GetObj(node, 'body'));
  END
  ELSE IF nt = 'ProcCallStmt' THEN
  BEGIN
    pname := GetStr(node, 'name');
    args_arr := GetObj(node, 'args');
    nargs := cJSON_GetArraySize(args_arr);
    IF (pname = 'WRITELN') OR (pname = 'WRITE') OR (pname = 'READLN') OR (pname = 'READ') THEN
    BEGIN
      { A leading file-variable argument (WRITE(F, ...) / READ(F, ...))
        selects the destination/source file instead of being a data
        argument -- detect and skip it, requiring it be a TEXT file (per
        the manual, a binary FILE isn't valid here). WRITE/WRITELN args are
        always WriteArg-wrapped (even the file selector); READ/READLN args
        never are. }
      start_arg := 0;
      IF nargs > 0 THEN
      BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) = 'WriteArg' THEN wexpr := GetObj(warg, 'expr') ELSE wexpr := warg;
        IF NodeType(wexpr) = 'Identifier' THEN
        BEGIN
          si := LookupSymbol(GetStr(wexpr, 'name'));
          IF (si <> 0) AND (symbols[si].tk = TK_FILE) THEN
          BEGIN
            IF (symbols[si].aux <> TK_CHAR) OR (symbols[si].aux2 <> 1) THEN
              AddError('WRITE/WRITELN/READ/READLN file selector must be a TEXT file');
            start_arg := 1;
          END;
        END;
      END;
      FOR i := start_arg TO nargs - 1 DO
      BEGIN
        warg := cJSON_GetArrayItem(args_arr, i);
        IF NodeType(warg) = 'WriteArg' THEN
        BEGIN
          wexpr := GetObj(warg, 'expr');
          IF wexpr <> NIL THEN cond_tk := CheckExpr(wexpr);
        END;
      END;
    END
    ELSE IF (pname = 'RESET') OR (pname = 'REWRITE') OR (pname = 'GET') OR
            (pname = 'PUT') OR (pname = 'CLOSE') OR (pname = 'DISCARD') THEN
    BEGIN
      { All six file primitives take exactly one bare file-variable argument
        (of any structure, TEXT or binary -- unlike WRITE/READ/EOLN, none of
        these care whether the file is TEXT). }
      IF nargs <> 1 THEN
        AddError('Argument count mismatch')
      ELSE BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('file primitive argument must be a bare file variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddError('Undefined identifier')
          ELSE IF symbols[si].tk <> TK_FILE THEN
            AddError('file primitive argument must be a FILE variable');
        END;
      END;
    END
    ELSE IF pname = 'ASSIGN' THEN
    BEGIN
      IF nargs <> 2 THEN
        AddError('ASSIGN expects exactly two arguments')
      ELSE BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('ASSIGN argument 1 must be a bare file variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddError('Undefined identifier')
          ELSE IF symbols[si].tk <> TK_FILE THEN
            AddError('ASSIGN argument 1 must be a FILE variable');
        END;
        cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
        IF (cond_tk <> TK_STRING) AND (cond_tk <> TK_CHAR) AND (cond_tk <> TK_UNKNOWN) THEN
          AddError('ASSIGN argument 2 must be STRING, LSTRING, or CHAR');
      END;
    END
    ELSE IF pname = 'READSET' THEN
    BEGIN
      { READSET([file,] dest, set_of_char): manual-documented extended I/O
        builtin (djvu.txt), reads from `file` (INPUT if omitted) into `dest`
        until a delimiter char in `set_of_char` is seen. Mirrors the
        WRITE/READ file-selector detection above; dest is required to be
        assignable and LSTRING-shaped -- this coarse model conflates
        STRING/LSTRING into TK_STRING (see ResolveTypeExpr's NamedType
        case), so both are accepted here the same way ASSIGN's second
        argument already is. }
      IF (nargs <> 2) AND (nargs <> 3) THEN
        AddError('READSET expects 2 or 3 arguments')
      ELSE BEGIN
        start_arg := 0;
        IF nargs = 3 THEN
        BEGIN
          warg := cJSON_GetArrayItem(args_arr, 0);
          IF NodeType(warg) <> 'Identifier' THEN
            AddError('READSET file argument must be a bare file variable')
          ELSE BEGIN
            si := LookupSymbol(GetStr(warg, 'name'));
            IF si = 0 THEN
              AddError('Undefined identifier')
            ELSE IF (symbols[si].tk <> TK_FILE) OR (symbols[si].aux <> TK_CHAR) OR (symbols[si].aux2 <> 1) THEN
              AddError('READSET file argument must be a TEXT file');
          END;
          start_arg := 1;
        END;
        warg := cJSON_GetArrayItem(args_arr, start_arg);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('READSET destination must be a bare LSTRING variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddError('Undefined identifier')
          ELSE IF symbols[si].tk <> TK_STRING THEN
            AddError('READSET destination must be STRING or LSTRING');
        END;
        cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, start_arg + 1));
        IF cond_tk <> TK_SET THEN
          AddError('READSET set argument must be a SET OF CHAR value');
      END;
    END
    ELSE IF (pname = 'NEW') OR (pname = 'DISPOSE') THEN
    BEGIN
      { Mirrors codegen.pas's own arity/shape checks (its NEW/DISPOSE case
        is the only place this dialect's short-form allocation is actually
        lowered) so a well-typed NEW/DISPOSE call reaches codegen instead
        of being rejected here first as "Undefined procedure" -- this file
        previously had no handling of either name at all. NEW's second
        (SUPER ARRAY upper-bound) argument isn't modeled here -- this file
        has no is_super concept -- so it's checked leniently, same as
        CONCAT below: codegen itself decides whether a second argument is
        actually required or accepted for a given pointee type. }
      IF ((pname = 'DISPOSE') AND (nargs <> 1)) OR
         ((pname = 'NEW') AND (nargs <> 1) AND (nargs <> 2)) THEN
        AddError('Argument count mismatch')
      ELSE BEGIN
        warg := cJSON_GetArrayItem(args_arr, 0);
        IF NodeType(warg) <> 'Identifier' THEN
          AddError('NEW/DISPOSE argument must be a bare pointer variable')
        ELSE BEGIN
          si := LookupSymbol(GetStr(warg, 'name'));
          IF si = 0 THEN
            AddError('Undefined identifier')
          ELSE IF symbols[si].tk <> TK_POINTER THEN
            AddError('NEW/DISPOSE argument must be a POINTER variable');
        END;
        IF nargs = 2 THEN
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, 1));
      END;
    END
    ELSE IF pname = 'CONCAT' THEN
    BEGIN
      { CONCAT(VAR d: LSTRING-or-STRING-or-Str255; CONST s: STRING-or-
        LSTRING-or-literal): the language's own built-in string-append
        procedure (distinct from codegen.pas's own target-language CONCAT
        support, which reads this same AST node shape but for a *user*
        program's CONCAT call) -- not otherwise special-cased anywhere in
        this file, so every native .pas source that calls it as a bare
        statement (codegen.pas does, heavily, to build up format strings)
        previously hit "Undefined procedure" here. Checked leniently, same
        as WRITE/WRITELN above: this file's coarse tk model has no
        separate Str255/STRING/LSTRING distinction worth enforcing here. }
      IF nargs <> 2 THEN
        AddError('CONCAT requires exactly two arguments')
      ELSE
        FOR i := 0 TO nargs - 1 DO
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
    END
    ELSE BEGIN
      si := LookupSymbol(pname);
      IF si = 0 THEN
      BEGIN
        AddError('Undefined procedure');
        FOR i := 0 TO nargs - 1 DO
          cond_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
      END
      ELSE BEGIN
        { Same [VARARGS] arity relaxation as CheckFuncCall above. }
        IF (nargs <> symbols[si].nparams)
           AND NOT (symbols[si].is_vararg AND (nargs > symbols[si].nparams)) THEN
          AddError('Argument count mismatch')
        ELSE
          FOR i := 0 TO nargs - 1 DO
          BEGIN
            expr_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
            IF i < symbols[si].nparams THEN
              IF NOT CanAssign(symbols[si].param_tk[i + 1], expr_tk) THEN
                AddError('Argument type mismatch');
          END;
      END;
    END;
  END
  ELSE IF nt = 'CompoundStmt' THEN
    CheckCompoundOrStmt(node)
  ELSE IF nt = 'LabelStmt' THEN
    { <label>: <stmt> -- the label declaration/target itself isn't checked
      (matching the Python reference, which builds no label table and
      leaves GOTO unchecked; codegen.pas is the enforcement point for
      "GOTO to undefined label", same as the reference), but the *inner*
      statement must still be walked. Omitting this case previously meant
      any statement reached only via a label silently skipped type
      checking -- the same class of bug as the historical CompoundStmt
      dispatch gap (see this file's header comment / §1.7). }
    CheckStmt(GetObj(node, 'stmt'))
  ELSE IF nt = 'GotoStmt' THEN
    { No-op: see the LabelStmt case's comment above. }
    BEGIN END
  ELSE IF nt = 'WithStmt' THEN
  BEGIN
    { WITH t1, t2, ... DO body -- equivalent to WITH t1 DO WITH t2 DO ...
      DO body (djvu.txt:10194-10198): push one scope per target left to
      right, each target's fields becoming bare identifiers visible in the
      inner scope, so a later target's field of the same name shadows an
      earlier one -- LookupSymbol's backward scan gives this for free. Only
      a RECORD-typed target is legal; a bare pointer-to-record is rejected
      (must be explicitly DEREF'd first), matching the reference and the
      manual. }
    with_targets := GetObj(node, 'targets');
    n_with_targets := cJSON_GetArraySize(with_targets);
    pushed := 0;
    FOR wi := 0 TO n_with_targets - 1 DO
    BEGIN
      with_target := cJSON_GetArrayItem(with_targets, wi);
      with_tk := CheckDesignator(with_target);
      IF with_tk = TK_RECORD THEN
      BEGIN
        rec_id := last_designator_aux;
        PushScope;
        pushed := pushed + 1;
        FOR fi := 1 TO nfields DO
          IF fields[fi].record_id = rec_id THEN
            si := DefineSymbol(fields[fi].fname, 'VAR', fields[fi].ftk, fields[fi].faux, fields[fi].faux2, 0);
      END
      ELSE IF with_tk <> TK_UNKNOWN THEN
        AddError('WITH target must be a record');
    END;
    CheckCompoundOrStmt(GetObj(node, 'body'));
    FOR wi := 1 TO pushed DO
      PopScope;
  END;
  END;
  stmt_depth := stmt_depth - 1;
END;

{ ============================== declarations ============================ }

PROCEDURE CheckBlock(block: ADRMEM); FORWARD;

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
  is_vararg: BOOLEAN;
  prior: INTEGER32;
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
    tk := CheckExpr(GetObj(decl, 'value'));
    si := DefineSymbol(dname, 'CONST', tk, 0, 0, 0);
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
      compiland. That last one has no body of its own, so the body <> NIL
      half already excludes it. Plain AND is not short-circuit in this
      dialect, hence the nested IFs rather than one conjunction. }
    body := GetObj(decl, 'body');
    prior := LookupSymbolInScope(dname);
    IF prior >= 1 THEN
      IF symbols[prior].is_extern THEN
        IF body <> NIL THEN
          AddError2('EXTERN routine cannot be defined here (use FORWARD): ', dname);

    si := DefineSymbol(dname, nt, TK_UNKNOWN, 0, 0, 0);
    IF nt = 'FuncDecl' THEN
      symbols[si].kind := 'FUNC'
    ELSE
      symbols[si].kind := 'PROC';
    symbols[si].ret_tk := ret_tk;
    symbols[si].is_extern := IsForeignRoutineDecl(decl);
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
    attrs_arr := GetObj(decl, 'attributes');
    nattrs := cJSON_GetArraySize(attrs_arr);
    FOR ai := 0 TO nattrs - 1 DO
    BEGIN
      attr_item := cJSON_GetArrayItem(attrs_arr, ai);
      IF GetStr(attr_item, 'name') = 'VARARGS' THEN is_vararg := TRUE;
    END;
    symbols[si].is_vararg := is_vararg;

    { Check the routine body (if any) in its own scope, with parameters
      bound and -- for a FUNCTION -- cur_func_name/cur_func_ret_tk/aux/aux2
      set so `F := expr` inside F's own body resolves as a return-slot
      assignment (see CheckStmt's AssignStmt case) without a shadow symbol
      that would otherwise hide F's own FUNC entry from recursive calls. }
    IF body <> NIL THEN
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

FUNCTION IsForeignRoutineDecl(decl: ADRMEM): BOOLEAN;
{ True for a routine whose body deliberately lives outside this compiland --
  a [C] library entry (puts, malloc, the LLVM-C API), or an EXTERN/EXTERNAL
  Pascal routine defined in a separately compiled object. An IMPLEMENTATION
  cannot supply a body for one of these, so ValidateImplementationContract
  below must not demand one.

  Mirrors codegen_decl.inc's IsCForeignDecl, but deliberately broader: that
  one answers "does this need the SysV C ABI", which requires [C] *and* an
  extern marker, whereas this one answers "is a Pascal body impossible", for
  which either marker alone is enough.

  Note this checks the interface's own declarations rather than filtering by
  the UNIT export list. The Python reference validates the contract by
  looping the export list instead, which would also let a [C] declaration
  through -- but it silently skips validation entirely for a unit written
  `UNIT foo;` with no parenthesised list, which is exactly the shape
  src/cg_base.inc uses. Exempting by kind keeps the contract enforced there. }
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
    { A bare `attr_nm = 'C'` comparison doesn't typecheck: a single-quoted
      single-character literal lexes as CHAR, not a length-1 LSTRING, so
      LSTRING = CHAR has no defined comparison. Compare the length byte
      (index 0, per the LSTRING index-0-is-length-as-CHAR convention) and
      the first character instead -- same idiom as codegen_decl.inc:504. }
    IF (ORD(attr_nm[0]) = 1) AND (attr_nm[1] = 'C') THEN found := TRUE;
    IF attr_nm = 'EXTERN' THEN found := TRUE;
    IF attr_nm = 'EXTERNAL' THEN found := TRUE;
  END;
  directive := GetStr(decl, 'directive');
  IF directive = 'EXTERN' THEN found := TRUE;
  IF directive = 'EXTERNAL' THEN found := TRUE;
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
BEGIN
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
END;

{ ============================== I/O driver =============================== }
{ ReadAllStdin now lives in jsonutil. }

FUNCTION GetObjOrNil(obj: ADRMEM; key: Str255): ADRMEM;
{ GetObj, but folding a "present but JSON null" field (e.g. an unparenthesized
  `USES unit;`'s 'imports', serialized as null rather than omitted) down to
  NIL too -- matches codegen.pas's own GetObjOrNil, needed here for the same
  reason: a bare GetObj<>NIL check would otherwise treat "no imports" as "an
  empty, non-NIL imports list" and filter every declaration out. }
VAR
  v: ADRMEM;
BEGIN
  v := GetObj(obj, key);
  IF (v <> NIL) AND (cJSON_IsNull(v) <> 0) THEN v := NIL;
  GetObjOrNil := v;
END;

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
BEGIN
  ifaces := GetObj(root, 'local_interfaces');
  IF ifaces <> NIL THEN
  BEGIN
    n := cJSON_GetArraySize(ifaces);
    FOR ni := 0 TO n - 1 DO
    BEGIN
      iface := cJSON_GetArrayItem(ifaces, ni);
      decls_arr := GetObj(iface, 'decls');
      m := cJSON_GetArraySize(decls_arr);
      FOR di := 0 TO m - 1 DO
        CheckDecl(cJSON_GetArrayItem(decls_arr, di));
    END;
  END;
END;

VAR
  root: ADRMEM;
  out_str: ADRMEM;
  i: INTEGER32;
  res_c: CINT;

BEGIN
  nsymbols := 0;
  scope_top := 0;
  ntypes := 0;
  nfields := 0;
  next_record_id := 1;
  nerrors := 0;
  expr_depth := 0;
  stmt_depth := 0;
  cur_func_ret_tk := TK_VOID;
  cur_func_aux := 0;
  cur_func_aux2 := 0;
  cur_func_name := '';

  root := ReadAllStdin;
  CheckLocalInterfaces(root);
  CheckLocalInterfaceUses(root, GetObj(root, 'local_interfaces'));
  CheckUnit(root);

  IF nerrors > 0 THEN
  BEGIN
    EPrint('Type checking failed:');
    FOR i := 1 TO nerrors DO
      EPrint(errors[i]);
    exit(1);
  END;

  out_str := cJSON_Print(root);
  res_c := puts(out_str);
END.
