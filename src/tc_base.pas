{ Shared-state implementation for the native type checker. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
IMPLEMENTATION OF tc_base;

FUNCTION cJSON_IsNull(item: ADRMEM): CINT [C]; EXTERN;

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

FUNCTION UpperStr(s: Str255): Str255;
{ ASCII case fold, matching codegen's cg_util.pas UpperStr. Identifiers are
  matched case-insensitively per the manual: "Lowercase and uppercase letters
  are interchangeable, except in string literals" (IBM Pascal, Aug 1981,
  Syntax and Vocabulary). }
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
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  i := nsymbols;
  WHILE (i >= 1) AND THEN (UpperStr(symbols[i].name) <> uname) DO
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
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  IF scope_top = 0 THEN base := 0
  ELSE base := scope_stack[scope_top];
  i := nsymbols;
  WHILE (i > base) AND THEN (UpperStr(symbols[i].name) <> uname) DO
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
{ Case-insensitive -- see UpperStr. Both sides are folded rather than the
  table being stored folded, so types[].name keeps the program's spelling. }
VAR
  i: INTEGER32;
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  i := ntypes;
  WHILE (i >= 1) AND THEN (UpperStr(types[i].name) <> uname) DO
    i := i - 1;
  LookupType := i;
END;

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

PROCEDURE TcInit;
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
END;

BEGIN
END.
