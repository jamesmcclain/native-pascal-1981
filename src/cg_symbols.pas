{ Implementations for cg_symbols. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
IMPLEMENTATION OF cg_symbols;

{ ============================ symbol table ============================== }

FUNCTION LookupSym(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
  found: INTEGER32;
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  found := 0;
  FOR i := 1 TO nsymbols DO
    IF UpperStr(symbols[i].name) = uname THEN found := i;
  LookupSym := found;
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

FUNCTION CurScopeBase: INTEGER32;
BEGIN
  IF scope_top = 0 THEN CurScopeBase := 0
  ELSE CurScopeBase := scope_stack[scope_top];
END;

PROCEDURE DeclareVar(name: Str255; tk: INTEGER);
VAR
  gvar, zero: ADRMEM;
  i, base: INTEGER32;
  dup, reuse_decl: BOOLEAN;
  uname: Str255;
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
         (TypeKind(tk) = TK_FILE) OR (tk = TK_ADRMEM) THEN
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
    IF in_local_scope THEN
      gvar := EntryAlloca(LLVMTypeForTk(tk), name)
    ELSE
    BEGIN
      gvar := LLVMAddGlobal(modl, LLVMTypeForTk(tk), MakeCStr(name));
      IF NOT lowering_spliced_interface THEN
      BEGIN
        IF (TypeKind(tk) = TK_ARRAY) OR (TypeKind(tk) = TK_RECORD) OR
           (TypeKind(tk) = TK_LSTRING) OR (TypeKind(tk) = TK_POINTER) OR
           (TypeKind(tk) = TK_STRING) OR (TypeKind(tk) = TK_SET) OR
           (TypeKind(tk) = TK_FILE) OR (tk = TK_ADRMEM) THEN
          zero := LLVMConstNull(LLVMTypeForTk(tk))
        ELSE IF (tk = TK_REAL) OR (tk = TK_REAL32) THEN zero := LLVMConstReal(LLVMTypeForTk(tk), 0.0)
        ELSE zero := LLVMConstInt(LLVMTypeForTk(tk), 0, 0);
        LLVMSetInitializer(gvar, zero);
      END;
    END;
    IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
    nsymbols := nsymbols + 1;
    symbols[nsymbols].name := name;
    symbols[nsymbols].tk := tk;
    symbols[nsymbols].llvm_val := gvar;
  END;
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

FUNCTION LookupRoutine(name: Str255): INTEGER32;
VAR
  i: INTEGER32;
  found: INTEGER32;
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  found := 0;
  FOR i := 1 TO nroutines DO
    IF UpperStr(routines[i].name) = uname THEN found := i;
  LookupRoutine := found;
END;

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
