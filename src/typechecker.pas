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

  MAX_SYMBOLS = 2000;
  MAX_TYPES   = 500;
  MAX_FIELDS  = 2000;
  MAX_ERRORS  = 200;
  MAX_PARAMS  = 16;

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

  errors: ARRAY [1..MAX_ERRORS] OF Str255;
  nerrors: INTEGER32;

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

FUNCTION IsOrdinal(tk: INTEGER): BOOLEAN;
BEGIN
  IsOrdinal := (tk = TK_INTEGER) OR (tk = TK_WORD) OR (tk = TK_CHAR) OR (tk = TK_BOOLEAN);
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
        AddFieldEntry(rid, nm, inner_tk, inner_aux, inner_aux2);
      END;
    END;
    tk := TK_RECORD;
    aux := rid;
  END;
END;

{ ============================ forward decls ============================ }

FUNCTION CheckExpr(node: ADRMEM): INTEGER; FORWARD;
PROCEDURE CheckStmt(node: ADRMEM); FORWARD;

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
      IF tk <> TK_POINTER THEN
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
  CheckDesignator := tk;
END;

FUNCTION CheckFuncCall(node: ADRMEM): INTEGER;
VAR
  name: Str255;
  args_arr: ADRMEM;
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
      IF (atk <> TK_INTEGER) AND (atk <> TK_WORD) AND (atk <> TK_CHAR) AND (atk <> TK_UNKNOWN) THEN
        AddError('SUCC/PRED argument must be INTEGER, WORD, or CHAR');
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
  si := LookupSymbol(name);
  IF si = 0 THEN
  BEGIN
    AddError('Undefined function');
    FOR i := 0 TO nargs - 1 DO
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
    CheckFuncCall := TK_UNKNOWN;
    RETURN;
  END;
  IF nargs <> symbols[si].nparams THEN
    AddError('Argument count mismatch')
  ELSE
    FOR i := 0 TO nargs - 1 DO
    BEGIN
      atk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
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
BEGIN
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
  nargs, i: INTEGER32;
  pname: Str255;
BEGIN
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
      FOR i := 0 TO nargs - 1 DO
      BEGIN
        warg := cJSON_GetArrayItem(args_arr, i);
        IF NodeType(warg) = 'WriteArg' THEN
        BEGIN
          wexpr := GetObj(warg, 'expr');
          IF wexpr <> NIL THEN cond_tk := CheckExpr(wexpr);
        END;
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
        IF nargs <> symbols[si].nparams THEN
          AddError('Argument count mismatch')
        ELSE
          FOR i := 0 TO nargs - 1 DO
          BEGIN
            expr_tk := CheckExpr(cJSON_GetArrayItem(args_arr, i));
            IF NOT CanAssign(symbols[si].param_tk[i + 1], expr_tk) THEN
              AddError('Argument type mismatch');
          END;
      END;
    END;
  END
  ELSE IF nt = 'CompoundStmt' THEN
    CheckCompoundOrStmt(node);
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
    si := DefineSymbol(dname, nt, TK_UNKNOWN, 0, 0, 0);
    IF nt = 'FuncDecl' THEN
      symbols[si].kind := 'FUNC'
    ELSE
      symbols[si].kind := 'PROC';
    symbols[si].ret_tk := ret_tk;
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

    { Check the routine body (if any) in its own scope, with parameters
      bound and -- for a FUNCTION -- cur_func_name/cur_func_ret_tk/aux/aux2
      set so `F := expr` inside F's own body resolves as a return-slot
      assignment (see CheckStmt's AssignStmt case) without a shadow symbol
      that would otherwise hide F's own FUNC entry from recursive calls. }
    body := GetObj(decl, 'body');
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
      init_body := GetObj(root, 'init_body');
      IF init_body <> NIL THEN CheckStmtList(init_body);
    END;
  END;
END;

{ ============================== I/O driver =============================== }
{ ReadAllStdin now lives in jsonutil. }

PROCEDURE CheckLocalInterfaces(root: ADRMEM);
{ USES X splices X's INTERFACE into this file's local_interfaces list (see
  units.py's check_program_unit): each entry's decls are signature-only (no
  body -- the real IMPLEMENTATION is a separately-compiled/linked object), so
  running them through the ordinary CheckDecl dispatch registers their TYPEs
  and PROC/FUNC signatures as callable symbols exactly like an EXTERN decl,
  with no body to check. }
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
  cur_func_ret_tk := TK_VOID;
  cur_func_aux := 0;
  cur_func_aux2 := 0;
  cur_func_name := '';

  root := ReadAllStdin;
  CheckLocalInterfaces(root);
  CheckUnit(root);

  IF nerrors > 0 THEN
  BEGIN
    res_c := puts(MakeCStr('Type checking failed:'));
    FOR i := 1 TO nerrors DO
      res_c := puts(MakeCStr(errors[i]));
    exit(1);
  END;

  out_str := cJSON_Print(root);
  res_c := puts(out_str);
END.
