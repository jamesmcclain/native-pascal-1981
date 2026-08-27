{ Implementations for cg_decl. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
(*$INCLUDE:'cg_expr.inc'*)
(*$INCLUDE:'cg_io.inc'*)
(*$INCLUDE:'cg_stmt.inc'*)
(*$INCLUDE:'cg_decl.inc'*)
IMPLEMENTATION OF cg_decl;

{ ============================== declarations =============================== }

{ ============================== declarations =============================== }

PROCEDURE CodegenDecl(decl: ADRMEM); FORWARD;
FUNCTION IsExternDirectiveDecl(decl: ADRMEM): BOOLEAN; FORWARD;

PROCEDURE CodegenDeclList(decls_arr: ADRMEM);
VAR
  n, i: INTEGER32;
BEGIN
  n := ArrSize(decls_arr);
  FOR i := 0 TO n - 1 DO
    CodegenDecl(ArrItem(decls_arr, i));
END;

FUNCTION SameIdentifier(a, b: Str255): BOOLEAN;
{ Case-insensitive identifier comparison. Symbol lookup elsewhere in this file
  is exact-case (the front end hands identifiers through unchanged), but a USES
  clause is matched against a UNIT heading written in a different file, where
  the two spellings routinely differ in case -- and mismatching them here would
  reject a program that otherwise compiles. }
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

FUNCTION FindUnitIndex(local_ifaces: ADRMEM; unit_name: Str255): INTEGER32;
{ 1-based index of unit_name within local_ifaces (case-insensitive), or 0. }
VAR
  nifaces, fi: INTEGER32;
BEGIN
  FindUnitIndex := 0;
  IF local_ifaces <> NIL THEN
  BEGIN
    nifaces := ArrSize(local_ifaces);
    FOR fi := 0 TO nifaces - 1 DO
      IF SameIdentifier(GetStr(ArrItem(local_ifaces, fi), 'name'), unit_name) THEN
        FindUnitIndex := fi + 1;
  END;
END;

PROCEDURE DFSVisitUnit(local_ifaces: ADRMEM; idx: INTEGER32);
{ Post-order DFS over the USES graph rooted at local_ifaces[idx-1], recording
  a dependency-before-dependent visit order into unit_order and detecting
  cycles via unit_visit_state (0=unvisited, 1=in progress/on the current DFS
  path, 2=finished). A cycle is a USES edge back to an in-progress unit --
  reported by name rather than left to surface as a duplicate-symbol splice
  failure or (for a genuinely self-referential include graph) an infinite
  splice loop. }
VAR
  iface, uses_arr, clause: ADRMEM;
  nu, ui, dep_idx: INTEGER32;
  dep_name, this_name: Str255;
BEGIN
  IF unit_visit_state[idx] <> 2 THEN
  BEGIN
    this_name := GetStr(ArrItem(local_ifaces, idx - 1), 'name');
    IF unit_visit_state[idx] = 1 THEN
      AbortWith2('codegen: circular USES dependency detected involving unit: ', this_name);
    unit_visit_state[idx] := 1;

    iface := ArrItem(local_ifaces, idx - 1);
    uses_arr := GetObj(iface, 'uses');
    IF uses_arr <> NIL THEN
    BEGIN
      nu := ArrSize(uses_arr);
      FOR ui := 0 TO nu - 1 DO
      BEGIN
        clause := ArrItem(uses_arr, ui);
        dep_name := GetStr(clause, 'name');
        dep_idx := FindUnitIndex(local_ifaces, dep_name);
        { A dependency with no spliced header of its own is reported by
          CheckUsesClauses's own direct-USES check below; nothing further to
          traverse here. }
        IF dep_idx <> 0 THEN
          DFSVisitUnit(local_ifaces, dep_idx);
      END;
    END;

    unit_visit_state[idx] := 2;
    { A DEVICE unit never gets a pascal_init_<name> (see codegen's own
      is_device_root guard around the ImplementationUnit/ModuleUnit init
      emission): its dependencies are still walked above for cycle
      detection, but it has nothing EmitUnitInitCalls could safely call, so
      it's left out of unit_order entirely rather than becoming a call to
      an undefined symbol. }
    IF NOT GetBool(iface, 'is_device') THEN
    BEGIN
      IF n_unit_order >= MAX_UNITS THEN
        AbortWith('codegen: too many units in one USES dependency graph');
      n_unit_order := n_unit_order + 1;
      unit_order[n_unit_order] := this_name;
    END;
  END;
END;

PROCEDURE BuildUnitInitOrder(root, local_ifaces: ADRMEM);
{ Populates unit_order[1..n_unit_order] with every unit transitively reached
  from root's own USES clauses, dependencies before dependents, each named
  exactly once -- consumed by CodegenProgramUnitInits to call each unit's
  pascal_init_<name> in a safe order, and doubles as the cycle-detection pass
  for CheckUsesClauses. }
VAR
  uses_arr, clause: ADRMEM;
  nclauses, ci, idx, nifaces, i: INTEGER32;
  unit_name: Str255;
BEGIN
  n_unit_order := 0;
  IF local_ifaces <> NIL THEN
  BEGIN
    nifaces := ArrSize(local_ifaces);
    FOR i := 1 TO nifaces DO unit_visit_state[i] := 0;
  END;
  uses_arr := GetObj(root, 'uses');
  IF uses_arr <> NIL THEN
  BEGIN
    nclauses := ArrSize(uses_arr);
    FOR ci := 0 TO nclauses - 1 DO
    BEGIN
      clause := ArrItem(uses_arr, ci);
      unit_name := GetStr(clause, 'name');
      idx := FindUnitIndex(local_ifaces, unit_name);
      IF idx <> 0 THEN DFSVisitUnit(local_ifaces, idx);
    END;
  END;
END;

PROCEDURE EmitUnitInitCalls;
{ Emits a call to pascal_init_<name>() for every unit in unit_order (built
  by BuildUnitInitOrder/DFSVisitUnit from this PROGRAM's own USES graph),
  dependencies before dependents, each exactly once -- only a PROGRAM's own
  main walks the whole graph this way; a MODULE/IMPLEMENTATION compiland
  that itself USES other units does not call their inits on its own behalf,
  since that would call some units' inits more than once across a multi-unit
  link. Declares each pascal_init_<name> fresh here rather than reusing any
  existing extern: the target is defined in a *separately compiled* object
  (the unit's own IMPLEMENTATION, which -- see the is_implementation case
  below -- now always emits this function, even with an empty body, so the
  call here always has something real to link against). }
VAR
  i, j, len: INTEGER32;
  init_name, uname: Str255;
  init_fnty, init_fn, callres: ADRMEM;
BEGIN
  FOR i := 1 TO n_unit_order DO
  BEGIN
    uname := unit_order[i];
    len := ORD(uname[0]);
    FOR j := 1 TO len DO
      IF (uname[j] >= 'A') AND (uname[j] <= 'Z') THEN uname[j] := CHR(ORD(uname[j]) + 32);
    init_name := 'pascal_init_';
    CONCAT(init_name, uname);
    init_fnty := LLVMFunctionType(i32ty, NIL, 0, 0);
    init_fn := LLVMAddFunction(modl, MakeCStr(init_name), init_fnty);
    callres := LLVMBuildCall2(builder, init_fnty, init_fn, NIL, 0, MakeCStr(''));
  END;
END;

PROCEDURE BindUsesAlias(alias, ename: Str255);
{ `USES unit(alias)` binds alias to whatever ename (the export at that
  position in the unit's own heading) already resolved to when its real
  declaration was lowered under its own name a moment ago -- an *additional*
  routine-table/symbol-table entry sharing the same underlying LLVMValueRef,
  not a rename of the original. Renaming the original's own LLVM symbol
  would break linking: a UNIT's real exported symbol (the one its separately
  compiled IMPLEMENTATION object actually defines) has to keep its true
  spelling for `clang`/`ld` to resolve it, no matter what a given importer
  chooses to call it locally. Only PROCEDURE/FUNCTION and VAR exports can be
  aliased this way; TYPE/CONST renaming is not implemented (neither has a
  runtime symbol, so nothing stops a caller writing one, but no current
  fixture or Python-reference behavior needs it, and guessing at the right
  shape without one risks a silent gap of its own). }
VAR
  ri, si, i: INTEGER32;
BEGIN
  ri := LookupRoutine(ename);
  IF ri <> 0 THEN
  BEGIN
    IF nroutines >= MAX_ROUTINES THEN AbortWith('codegen: too many routines');
    nroutines := nroutines + 1;
    routines[nroutines].name := alias;
    routines[nroutines].is_func := routines[ri].is_func;
    routines[nroutines].fn := routines[ri].fn;
    routines[nroutines].fnty := routines[ri].fnty;
    routines[nroutines].ret_tk := routines[ri].ret_tk;
    routines[nroutines].nparams := routines[ri].nparams;
    FOR i := 1 TO routines[ri].nparams DO
    BEGIN
      routines[nroutines].param_tk[i] := routines[ri].param_tk[i];
      routines[nroutines].param_is_var[i] := routines[ri].param_is_var[i];
      routines[nroutines].param_needs_copy[i] := routines[ri].param_needs_copy[i];
    END;
    routines[nroutines].has_body := routines[ri].has_body;
    routines[nroutines].is_c := routines[ri].is_c;
    routines[nroutines].is_extern := routines[ri].is_extern;
    routines[nroutines].is_vararg := routines[ri].is_vararg;
  END
  ELSE
  BEGIN
    si := LookupSym(ename);
    IF si <> 0 THEN
    BEGIN
      IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
      nsymbols := nsymbols + 1;
      symbols[nsymbols].name := alias;
      symbols[nsymbols].tk := symbols[si].tk;
      symbols[nsymbols].llvm_val := symbols[si].llvm_val;
    END
    ELSE
      AbortWith2('codegen: USES import renames an export this compiler cannot alias (only PROCEDURE/FUNCTION/VAR are supported): ', ename);
  END;
END;

PROCEDURE CheckUsesClauses(root, local_ifaces: ADRMEM);
{ Reconcile the root's USES clauses against the INTERFACE headers spliced
  into the same source file, and (for a renaming clause) bind each alias via
  BindUsesAlias now that every local_interfaces declaration has already been
  lowered under its own real name. Also reports the other ways a USES clause
  can fail to be honored -- no spliced header for the named unit, and a
  circular USES graph -- instead of surfacing later as "unknown routine" at
  the call site or a duplicate-symbol splice failure. }
VAR
  uses_arr, clause, imports_arr, params_arr: ADRMEM;
  nclauses, ci, nifaces, fi, nimports, ii, nparams: INTEGER32;
  unit_name, alias, ename: Str255;
  found: BOOLEAN;
  matched_iface: ADRMEM;
BEGIN
  uses_arr := GetObj(root, 'uses');
  IF uses_arr <> NIL THEN
  BEGIN
    nclauses := ArrSize(uses_arr);
    FOR ci := 0 TO nclauses - 1 DO
    BEGIN
      clause := ArrItem(uses_arr, ci);
      unit_name := GetStr(clause, 'name');
      found := FALSE;
      matched_iface := NIL;
      IF local_ifaces <> NIL THEN
      BEGIN
        nifaces := ArrSize(local_ifaces);
        FOR fi := 0 TO nifaces - 1 DO
          IF SameIdentifier(GetStr(ArrItem(local_ifaces, fi), 'name'), unit_name) THEN
          BEGIN
            found := TRUE;
            matched_iface := ArrItem(local_ifaces, fi);
          END;
      END;
      IF NOT found THEN
        AbortWith2('codegen: USES unit needs a spliced INTERFACE header: ', unit_name);
      imports_arr := GetObjOrNil(clause, 'imports');
      IF imports_arr <> NIL THEN
      BEGIN
        params_arr := GetObj(matched_iface, 'params');
        nparams := ArrSize(params_arr);
        nimports := ArrSize(imports_arr);
        IF nimports > nparams THEN
          AbortWith('codegen: USES import list renames more names than the unit exports');
        FOR ii := 0 TO nimports - 1 DO
        BEGIN
          alias := CStrToStr255(cJSON_GetStringValue(ArrItem(imports_arr, ii)));
          ename := CStrToStr255(cJSON_GetStringValue(ArrItem(params_arr, ii)));
          BindUsesAlias(alias, ename);
        END;
      END;
    END;
  END;
  { Also walks the full transitive graph (not just root's direct clauses) so
    a cycle two or more hops away from root -- e.g. root USES beta USES
    alpha USES beta -- is still caught here rather than only when something
    downstream happens to walk that far. }
  BuildUnitInitOrder(root, local_ifaces);
END;

PROCEDURE InitFileStorage(slot: ADRMEM; elem_tid, structure: INTEGER; var_name: Str255);
{ Allocates the FCB + inline element buffer at the file variable's own
  storage site and stores an opaque i8* to the FCB into `slot` -- mirrors
  the reference's _init_file_storage field for field (see filefcbty's own
  comment for the field layout/order). INPUT/OUTPUT start pre-opened
  (mode 1); every other file starts unopened (mode 0) until RESET/REWRITE. }
VAR
  fcb, buf, gep_idx, field_ptr, zero: ADRMEM;
  elem_size, default_mode: INTEGER32;
  uname: Str255;
BEGIN
  elem_size := TypeSizeBytes(elem_tid);
  IF elem_size < 1 THEN elem_size := 1;
  fcb := EntryAlloca(filefcbty, 'file_fcb');
  buf := EntryAlloca(LLVMArrayType(i8ty, elem_size), 'file_buf');
  zero := LLVMConstInt(i32ty, 0, 0);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 0, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, elem_size, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 1, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, structure, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 2, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), field_ptr);

  uname := UpperStr(var_name);
  IF (uname = 'INPUT') OR (uname = 'OUTPUT') THEN default_mode := 1 ELSE default_mode := 0;
  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 3, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, default_mode, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 4, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMBuildBitCast(builder, buf, i8ptrty, MakeCStr('')), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 5, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 6, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstNull(i8ptrty), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 7, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 8, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i8ty, 0, 0), field_ptr);

  gep_idx := AllocPtrArray(2);
  SetPtrArrayElem(gep_idx, 0, zero);
  SetPtrArrayElem(gep_idx, 1, LLVMConstInt(i32ty, 9, 0));
  field_ptr := LLVMBuildGEP2(builder, filefcbty, fcb, gep_idx, 2, MakeCStr(''));
  LLVMBuildStore(builder, LLVMConstInt(i32ty, 0, 0), field_ptr);

  LLVMBuildStore(builder, LLVMBuildBitCast(builder, fcb, i8ptrty, MakeCStr('')), slot);
END;

PROCEDURE RegisterPredeclaredFiles;
{ Unconditionally declares INPUT/OUTPUT as TEXT-file symbols for the main
  PROGRAM, mirroring the reference's _register_predeclared_files -- without
  this, LoadFileFcbPtr('INPUT') aborts as undefined for any program that
  doesn't itself write VAR INPUT: TEXT, which is exactly the case READSET's
  2-argument implicit-INPUT form needs to cover. A no-op if the program
  already declared its own INPUT/OUTPUT (e.g. as an explicit heading
  parameter with its own VAR). }
VAR
  text_tid: INTEGER;
BEGIN
  IF LookupSym('INPUT') = 0 THEN
  BEGIN
    text_tid := RegisterType(TK_FILE, TK_CHAR, 0, 1, i8ptrty);
    DeclareVar('INPUT', text_tid);
    InitFileStorage(symbols[nsymbols].llvm_val, TK_CHAR, 1, 'INPUT');
  END;
  IF LookupSym('OUTPUT') = 0 THEN
  BEGIN
    text_tid := RegisterType(TK_FILE, TK_CHAR, 0, 1, i8ptrty);
    DeclareVar('OUTPUT', text_tid);
    InitFileStorage(symbols[nsymbols].llvm_val, TK_CHAR, 1, 'OUTPUT');
  END;
END;

PROCEDURE CodegenVarDecl(decl: ADRMEM);
VAR
  names: ADRMEM;
  tk: INTEGER;
  n, i: INTEGER32;
  vname: Str255;
BEGIN
  tk := ResolveTypeExpr(GetObj(decl, 'type_expr'));
  names := GetObj(decl, 'names');
  n := ArrSize(names);
  FOR i := 0 TO n - 1 DO
  BEGIN
    vname := CStrToStr255(cJSON_GetStringValue(ArrItem(names, i)));
    DeclareVar(vname, tk);
    IF TypeKind(tk) = TK_FILE THEN
      InitFileStorage(symbols[nsymbols].llvm_val, types[tk].elem_tid, types[tk].hi, vname);
  END;
END;

PROCEDURE ApplyLaunchBoundAttrs(decl, fn: ADRMEM);
{ NVPTX consumes launch bounds through legacy !nvvm.annotations metadata.
  They are ptxas facts, so no host-target approximation is emitted. }
VAR
  attrs, attr, args, mds, mdnode: ADRMEM;
  i, j, n, nargs: INTEGER32;
  nm, key: Str255;
BEGIN
  IF NOT is_nvptx_device THEN
    AbortWith('codegen: launch-bound attributes require an NVPTX DEVICE target');
  attrs := GetObj(decl, 'attributes');
  n := ArrSize(attrs);
  FOR i := 0 TO n - 1 DO
  BEGIN
    attr := ArrItem(attrs, i);
    nm := GetStr(attr, 'name');
    IF (nm = 'MAXNTID') OR (nm = 'REQNTID') OR (nm = 'MINCTASM') THEN
    BEGIN
      args := GetObj(attr, 'arg');
      nargs := ArrSize(args);
      FOR j := 0 TO nargs - 1 DO
      BEGIN
        IF nm = 'MAXNTID' THEN
        BEGIN
          IF j = 0 THEN key := 'maxntidx'
          ELSE IF j = 1 THEN key := 'maxntidy'
          ELSE key := 'maxntidz';
        END
        ELSE IF nm = 'REQNTID' THEN
        BEGIN
          IF j = 0 THEN key := 'reqntidx'
          ELSE IF j = 1 THEN key := 'reqntidy'
          ELSE key := 'reqntidz';
        END
        ELSE key := 'minctasm';
        mds := AllocPtrArray(3);
        SetPtrArrayElem(mds, 0, LLVMValueAsMetadata(fn));
        SetPtrArrayElem(mds, 1, LLVMMDStringInContext2(ctx, MakeCStr(key), ORD(key[0])));
        SetPtrArrayElem(mds, 2, LLVMValueAsMetadata(LLVMConstInt(i32ty, ResolveIntLiteral(ArrItem(args, j)), 0)));
        mdnode := LLVMMDNodeInContext2(ctx, mds, 3);
        LLVMAddNamedMetadataOperand(modl, MakeCStr('nvvm.annotations'), LLVMMetadataAsValue(ctx, mdnode));
      END;
    END;
  END;
END;

FUNCTION IsCForeignDecl(decl: ADRMEM): BOOLEAN;
{ True for an EXTERN/EXTERNAL routine carrying the [C] attribute -- mirrors
  the Python reference's CAbiMixin.is_c_abi_foreign (c_abi.py). Only routines
  answering TRUE here get the SysV MEMORY-class byval treatment for their
  needs_copy params (SysVAggClass below); every other routine keeps the
  plain-Pascal first-class-aggregate convention. }
VAR
  attrs_arr, item: ADRMEM;
  i, nattrs: INTEGER32;
  attr_nm, directive: Str255;
  has_c, has_extern_attr: BOOLEAN;
BEGIN
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := ArrSize(attrs_arr);
  has_c := FALSE;
  has_extern_attr := FALSE;
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    item := ArrItem(attrs_arr, i);
    { Attribute/directive names are already canonical uppercase in the AST
      (lexer keyword kinds, or the parser's own literal 'C' for [C]/[CDECL]
      -- see parser.pas ParseAttributeItem), so no case-folding is needed
      here, unlike c_abi.py's .upper() (which folds a Python-side string
      that isn't guaranteed pre-uppercased). }
    attr_nm := GetStr(item, 'name');
    { A bare `attr_nm = 'C'` comparison doesn't typecheck: single-quoted
      single-character literals lex as CHAR, not a length-1 LSTRING, so
      LSTRING = CHAR has no defined comparison. Compare the length byte
      (index 0, per the LSTRING index-0-is-length-as-CHAR convention) and
      the first character (index 1) instead -- mirrors the identical idiom
      at parser.pas:1882 for the same [C] attribute-name check. }
    IF (ORD(attr_nm[0]) = 1) AND (attr_nm[1] = 'C') THEN has_c := TRUE;
    IF (attr_nm = 'EXTERN') OR (attr_nm = 'EXTERNAL') THEN has_extern_attr := TRUE;
  END;
  directive := GetStr(decl, 'directive');
  IsCForeignDecl := has_c AND (has_extern_attr OR (directive = 'EXTERN') OR (directive = 'EXTERNAL'));
END;


FUNCTION IsVarargsDecl(decl: ADRMEM): BOOLEAN;
{ True for a routine carrying the [VARARGS] attribute -- the C variadic
  ellipsis, so the declared parameters are only the fixed prefix. Only
  meaningful on a [C] FOREIGN routine (the 1981 dialect gives a Pascal
  routine no way to read a variadic tail), so callers pair it with
  IsCForeignDecl and ignore it otherwise. The attribute name is already
  canonical uppercase in the AST, exactly as IsCForeignDecl above notes, and
  is longer than one character so it compares as a plain LSTRING. }
VAR
  attrs_arr, item: ADRMEM;
  i, nattrs: INTEGER32;
  found: BOOLEAN;
BEGIN
  attrs_arr := GetObj(decl, 'attributes');
  nattrs := ArrSize(attrs_arr);
  found := FALSE;
  FOR i := 0 TO nattrs - 1 DO
  BEGIN
    item := ArrItem(attrs_arr, i);
    IF GetStr(item, 'name') = 'VARARGS' THEN found := TRUE;
  END;
  IsVarargsDecl := found;
END;


PROCEDURE FlattenParams(params_arr: ADRMEM; VAR n: INTEGER32; VAR names: ParamNameArr;
                         VAR tks: ParamTkArr; VAR isvar: ParamVarArr; VAR needs_copy: ParamVarArr);
{ A Pascal formal-parameter section groups several names under one type
  (`a, b: INTEGER`); this flattens that grouping into parallel arrays of
  one entry per actual parameter, matching how llvm-c's LLVMFunctionType
  and the routine table both want one slot per parameter, not one per
  group. }
VAR
  np, pi, nn, ni: INTEGER32;
  param, pnames: ADRMEM;
  tk: INTEGER;
  is_v, needs_c: BOOLEAN;
BEGIN
  n := 0;
  np := ArrSize(params_arr);
  FOR pi := 0 TO np - 1 DO
  BEGIN
    param := ArrItem(params_arr, pi);
    tk := ResolveTypeExpr(GetObj(param, 'type_expr'));
    { VAR/VARS/CONST/CONSTS are all reference-mode at the ABI level -- CONST
      only additionally forbids mutation, a typechecker-level restriction,
      not a codegen one, so it is passed the same way as VAR here: as a
      pointer, never copied. }
    is_v := (GetStr(param, 'mode') = 'VAR') OR (GetStr(param, 'mode') = 'VARS') OR
            (GetStr(param, 'mode') = 'CONST') OR (GetStr(param, 'mode') = 'CONSTS');
    { A plain value-mode ARRAY/RECORD/LSTRING/STRING param: too large to
      pass as a raw LLVM value the way a scalar is, so it is passed as a
      pointer too (see needs_copy at the routine-entry/call-site level),
      but unlike VAR/CONST the callee must copy it so mutations don't leak
      back into the caller's own storage. }
    needs_c := (NOT is_v) AND ((TypeKind(tk) = TK_ARRAY) OR (TypeKind(tk) = TK_RECORD) OR
       (TypeKind(tk) = TK_LSTRING) OR (TypeKind(tk) = TK_STRING));
    pnames := GetObj(param, 'names');
    nn := ArrSize(pnames);
    FOR ni := 0 TO nn - 1 DO
    BEGIN
      IF n >= MAX_PARAMS THEN AbortWith('codegen: too many parameters');
      n := n + 1;
      names[n] := CStrToStr255(cJSON_GetStringValue(ArrItem(pnames, ni)));
      tks[n] := tk;
      isvar[n] := is_v;
      needs_copy[n] := needs_c;
    END;
  END;
END;

FUNCTION ParamNamesOf(decl: ADRMEM; VAR names: ParamNameArr): INTEGER32;
{ Flatten one declaration's formal-parameter names only -- deliberately not
  FlattenParams, which also resolves each type_expr and so would register
  types for routines that may never be lowered. The readonly analysis below
  runs before any body is lowered and needs nothing but the names. }
VAR
  params_arr, param, pnames: ADRMEM;
  np, pi, nn, ni, n: INTEGER32;
BEGIN
  n := 0;
  params_arr := GetObj(decl, 'params');
  np := ArrSize(params_arr);
  FOR pi := 0 TO np - 1 DO
  BEGIN
    param := ArrItem(params_arr, pi);
    pnames := GetObj(param, 'names');
    nn := ArrSize(pnames);
    FOR ni := 0 TO nn - 1 DO
      IF n < MAX_PARAMS THEN
      BEGIN
        n := n + 1;
        names[n] := CStrToStr255(cJSON_GetStringValue(ArrItem(pnames, ni)));
      END;
  END;
  ParamNamesOf := n;
END;

FUNCTION ReadonlyBareFormal(node: ADRMEM): INTEGER32;
{ The 1-based formal index this node is a *bare* use of (a plain identifier,
  or a selector-less designator), or 0. A bare use of a pointer formal hands
  its raw pointer value to whatever surrounds it, so outside the one context
  that is analyzable (a direct call actual) it counts as an escape. }
VAR
  nt, nm: Str255;
  i: INTEGER32;
BEGIN
  ReadonlyBareFormal := 0;
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    nm := '';
    IF nt = 'Identifier' THEN nm := GetStr(node, 'name')
    ELSE IF nt = 'Designator' THEN
      IF ArrSize(GetObj(node, 'selectors')) = 0 THEN nm := GetStr(node, 'name');
    IF nm <> '' THEN
      FOR i := 1 TO eff_nparams DO
        IF eff_pname[i] = nm THEN ReadonlyBareFormal := i;
  END;
END;

FUNCTION AssignWritesThroughFormal(node: ADRMEM): INTEGER32;
{ For an AssignStmt, the formal index written *through* (`p^... := x`), or 0.
  A write to the pointer variable itself (`p := q`) is not a write to the
  pointee and so does not disqualify readonly; the DEREF selector is what
  distinguishes the two. }
VAR
  target, sels, sel: ADRMEM;
  i, nsel, fi: INTEGER32;
  has_deref: BOOLEAN;
  nm: Str255;
BEGIN
  AssignWritesThroughFormal := 0;
  target := GetObj(node, 'target');
  IF NodeType(target) = 'Designator' THEN
  BEGIN
    nm := GetStr(target, 'name');
    fi := 0;
    FOR i := 1 TO eff_nparams DO
      IF eff_pname[i] = nm THEN fi := i;
    IF fi <> 0 THEN
    BEGIN
      sels := GetObj(target, 'selectors');
      nsel := ArrSize(sels);
      has_deref := FALSE;
      FOR i := 0 TO nsel - 1 DO
      BEGIN
        sel := ArrItem(sels, i);
        IF GetStr(sel, 'kind') = 'DEREF' THEN has_deref := TRUE;
      END;
      IF has_deref THEN AssignWritesThroughFormal := fi;
    END;
  END;
END;

PROCEDURE ScanReadonlyNode(node: ADRMEM);
{ Accumulate one routine body's effects on its own formals into the eff_*
  globals. Everything unrecognized fails closed: a bare formal anywhere but a
  direct call actual is an escape, and a WITH anywhere disqualifies the whole
  routine (WITH's field designators are not tied back to the originating
  pointer expression by this purely syntactic walk, so a write inside a WITH
  block could otherwise go unnoticed). }
CONST
  MAX_SCAN_ARGS = 64;
VAR
  nt: Str255;
  nchild, ci, nargs, ai, fi: INTEGER32;
  args, arg: ADRMEM;
  forwarded: ARRAY [1..MAX_SCAN_ARGS] OF BOOLEAN;
BEGIN
  IF node <> NIL THEN
  BEGIN
    nt := NodeType(node);
    { A nested routine is its own lexical body and its own call-graph node;
      its effects are summarized separately, not folded into this one. }
    IF (nt <> 'ProcDecl') AND (nt <> 'FuncDecl') THEN
    BEGIN
      IF nt = 'WithStmt' THEN eff_has_with := TRUE;
      IF nt = 'AssignStmt' THEN
      BEGIN
        fi := AssignWritesThroughFormal(node);
        IF fi <> 0 THEN eff_written[fi] := TRUE;
      END;
      IF (nt = 'FuncCall') OR (nt = 'ProcCallStmt') THEN
      BEGIN
        args := GetObj(node, 'args');
        nargs := ArrSize(args);
        FOR ai := 1 TO MAX_SCAN_ARGS DO forwarded[ai] := FALSE;
        IF nargs <= MAX_SCAN_ARGS THEN
          FOR ai := 0 TO nargs - 1 DO
          BEGIN
            arg := ArrItem(args, ai);
            fi := ReadonlyBareFormal(arg);
            IF fi <> 0 THEN
            BEGIN
              IF eff_ncalls >= MAX_CALL_EDGES THEN
                { Out of edge slots: fail closed by treating the forward as an
                  escape rather than dropping the fact on the floor. }
                eff_escaped[fi] := TRUE
              ELSE
              BEGIN
                eff_ncalls := eff_ncalls + 1;
                eff_call_formal[eff_ncalls] := fi;
                eff_call_callee[eff_ncalls] := GetStr(node, 'name');
                eff_call_argpos[eff_ncalls] := ai;
                forwarded[ai + 1] := TRUE;
              END;
            END;
          END;
        { A call node's only expression children are its actuals; the ones
          recognized as direct forwards above are summarized through the
          callee instead of being rescanned (which would call them escapes). }
        FOR ai := 0 TO nargs - 1 DO
          IF (nargs > MAX_SCAN_ARGS) OR (NOT forwarded[ai + 1]) THEN
            ScanReadonlyNode(ArrItem(args, ai));
      END
      ELSE
      BEGIN
        fi := ReadonlyBareFormal(node);
        IF fi <> 0 THEN eff_escaped[fi] := TRUE
        ELSE
        BEGIN
          { Generic descent: cJSON links an object's members and an array's
            elements through the same child list, so one loop walks both. }
          nchild := ArrSize(node);
          FOR ci := 0 TO nchild - 1 DO
            ScanReadonlyNode(ArrItem(node, ci));
        END;
      END;
    END;
  END;
END;

PROCEDURE ComputeReadonlyEffects(decl: ADRMEM);
{ Fill the eff_* globals for one declaration. Callers that then recurse into
  another routine's summary must copy the results out first. }
VAR
  i: INTEGER32;
  body: ADRMEM;
BEGIN
  eff_nparams := ParamNamesOf(decl, eff_pname);
  FOR i := 1 TO MAX_PARAMS DO
  BEGIN
    eff_written[i] := FALSE;
    eff_escaped[i] := FALSE;
  END;
  eff_has_with := FALSE;
  eff_ncalls := 0;
  body := GetObj(decl, 'body');
  IF (eff_nparams > 0) AND (NodeType(body) = 'Block') THEN
    ScanReadonlyNode(GetObj(body, 'body'));
END;

FUNCTION LookupDevRoutine(name: Str255): INTEGER32;
VAR
  i, found: INTEGER32;
BEGIN
  found := 0;
  FOR i := 1 TO dev_ro_count DO
    IF dev_ro_name[i] = name THEN found := i;
  LookupDevRoutine := found;
END;

PROCEDURE RegisterDevRoutines(decls: ADRMEM);
{ Record every body-bearing device routine, nested ones included, before any
  of them is lowered -- a kernel entry may call a helper declared later in
  the source. Body-less (interface/imported/EXTERN) declarations are left out
  so they fail closed, and a duplicate name is marked ambiguous rather than
  guessed about. }
VAR
  i, n, idx: INTEGER32;
  item, body: ADRMEM;
  nt, nm: Str255;
  pnames: ParamNameArr;
BEGIN
  n := ArrSize(decls);
  FOR i := 0 TO n - 1 DO
  BEGIN
    item := ArrItem(decls, i);
    nt := NodeType(item);
    IF (nt = 'ProcDecl') OR (nt = 'FuncDecl') THEN
    BEGIN
      body := GetObj(item, 'body');
      IF NodeType(body) = 'Block' THEN
      BEGIN
        nm := GetStr(item, 'name');
        idx := LookupDevRoutine(nm);
        IF idx <> 0 THEN dev_ro_dup[idx] := TRUE
        ELSE IF dev_ro_count < MAX_DEV_ROUTINES THEN
        BEGIN
          dev_ro_count := dev_ro_count + 1;
          dev_ro_name[dev_ro_count] := nm;
          dev_ro_decl[dev_ro_count] := item;
          dev_ro_nparams[dev_ro_count] := ParamNamesOf(item, pnames);
          dev_ro_dup[dev_ro_count] := FALSE;
          dev_ro_cached[dev_ro_count] := FALSE;
          dev_ro_busy[dev_ro_count] := FALSE;
        END;
        RegisterDevRoutines(GetObj(body, 'decls'));
      END;
    END;
  END;
END;

FUNCTION DeviceReadonlySummary(idx: INTEGER32; VAR ro: ParamVarArr): INTEGER32;
{ The formals of dev_ro_decl[idx] proven readonly across analyzable local
  helpers, returning the formal count and filling `ro`. Unknown callees,
  body-less/imported routines, ambiguous names, WITH, and call cycles all
  withhold the fact rather than guess. The result is per-parameter: a helper
  may write one buffer and stay readonly for another. }
VAR
  i, e, n, ncalls, cidx, cn, fi: INTEGER32;
  has_with: BOOLEAN;
  written, escaped, callee_ro: ParamVarArr;
  call_formal, call_argpos: ARRAY [1..MAX_CALL_EDGES] OF INTEGER32;
  call_callee: ARRAY [1..MAX_CALL_EDGES] OF Str255;
BEGIN
  IF dev_ro_cached[idx] THEN
  BEGIN
    FOR i := 1 TO MAX_PARAMS DO ro[i] := dev_ro_mask[idx][i];
    DeviceReadonlySummary := dev_ro_nparams[idx];
  END
  ELSE IF dev_ro_busy[idx] THEN
  BEGIN
    { Cycle: withhold everything, and do not cache -- the enclosing call in
      progress owns the real answer. }
    FOR i := 1 TO MAX_PARAMS DO ro[i] := FALSE;
    DeviceReadonlySummary := dev_ro_nparams[idx];
  END
  ELSE
  BEGIN
    dev_ro_busy[idx] := TRUE;
    ComputeReadonlyEffects(dev_ro_decl[idx]);
    n := eff_nparams;
    has_with := eff_has_with;
    ncalls := eff_ncalls;
    FOR i := 1 TO MAX_PARAMS DO
    BEGIN
      written[i] := eff_written[i];
      escaped[i] := eff_escaped[i];
    END;
    FOR e := 1 TO ncalls DO
    BEGIN
      call_formal[e] := eff_call_formal[e];
      call_callee[e] := eff_call_callee[e];
      call_argpos[e] := eff_call_argpos[e];
    END;
    FOR i := 1 TO MAX_PARAMS DO
      ro[i] := (i <= n) AND (NOT has_with) AND (NOT written[i]) AND (NOT escaped[i]);
    FOR e := 1 TO ncalls DO
    BEGIN
      fi := call_formal[e];
      IF ro[fi] THEN
      BEGIN
        cidx := LookupDevRoutine(call_callee[e]);
        IF cidx = 0 THEN ro[fi] := FALSE
        ELSE IF dev_ro_dup[cidx] THEN ro[fi] := FALSE
        ELSE
        BEGIN
          cn := DeviceReadonlySummary(cidx, callee_ro);
          IF call_argpos[e] >= cn THEN ro[fi] := FALSE
          ELSE IF NOT callee_ro[call_argpos[e] + 1] THEN ro[fi] := FALSE;
        END;
      END;
    END;
    dev_ro_busy[idx] := FALSE;
    dev_ro_cached[idx] := TRUE;
    FOR i := 1 TO MAX_PARAMS DO dev_ro_mask[idx][i] := ro[i];
    DeviceReadonlySummary := n;
  END;
END;

PROCEDURE ApplyKernelParamAttrs(decl, fn: ADRMEM; n: INTEGER32; VAR tks: ParamTkArr);
{ Attach the pointer-parameter facts LLVM cannot infer for a bare device
  pointer: natural alignment, dereferenceable, readonly/nocapture, and (only
  when explicitly opted into) noalias. Called for a real NVPTX kernel entry
  only, so this is inert on the CPU-device parity path. }
VAR
  i, cn: INTEGER32;
  idx: INTEGER32;
  ro: ParamVarArr;
  pointee: INTEGER;
  attr: ADRMEM;
BEGIN
  FOR i := 1 TO MAX_PARAMS DO ro[i] := FALSE;
  idx := 0;
  FOR i := 1 TO dev_ro_count DO
    IF dev_ro_decl[i] = decl THEN idx := i;
  IF idx <> 0 THEN cn := DeviceReadonlySummary(idx, ro);
  FOR i := 1 TO n DO
    IF TypeKind(tks[i]) = TK_POINTER THEN
    BEGIN
      pointee := types[tks[i]].elem_tid;
      { Natural alignment of the pointee: without it the NVPTX backend
        annotates every pointer parameter `.ptr .global .align 1`, though the
        element type is known and genuinely better aligned than that. }
      IF align_kind_id <> 0 THEN
      BEGIN
        attr := LLVMCreateEnumAttribute(ctx, align_kind_id, TypeAlignBytes(pointee));
        LLVMAddAttributeAtIndex(fn, i, attr);
      END;
      { dereferenceable(bytes): only for a statically sized pointee. A SUPER
        ARRAY has no static extent, and nothing ties such a buffer to
        whichever sibling parameter might carry its length, so no size is
        claimed for one. }
      IF (TypeKind(pointee) = TK_ARRAY) AND (NOT types[pointee].is_super) AND (deref_kind_id <> 0) THEN
      BEGIN
        attr := LLVMCreateEnumAttribute(ctx, deref_kind_id, TypeSizeBytes(pointee));
        LLVMAddAttributeAtIndex(fn, i, attr);
      END;
      IF ro[i] THEN
      BEGIN
        IF readonly_kind_id <> 0 THEN
        BEGIN
          attr := LLVMCreateEnumAttribute(ctx, readonly_kind_id, 0);
          LLVMAddAttributeAtIndex(fn, i, attr);
        END;
        IF nocapture_kind_id <> 0 THEN
        BEGIN
          attr := LLVMCreateEnumAttribute(ctx, nocapture_kind_id, 0);
          LLVMAddAttributeAtIndex(fn, i, attr);
        END
        ELSE IF captures_kind_id <> 0 THEN
        BEGIN
          attr := LLVMCreateEnumAttribute(ctx, captures_kind_id, 0); { captures(none) }
          LLVMAddAttributeAtIndex(fn, i, attr);
        END;
      END;
      IF noalias_kernel_params AND (noalias_kind_id <> 0) THEN
      BEGIN
        attr := LLVMCreateEnumAttribute(ctx, noalias_kind_id, 0);
        LLVMAddAttributeAtIndex(fn, i, attr);
      END;
    END;
END;

PROCEDURE CodegenRoutineDeclInner(decl: ADRMEM; is_func: BOOLEAN);
VAR
  name: Str255;
  params_arr, body_blk: ADRMEM;
  n: INTEGER32;
  names: ParamNameArr;
  tks: ParamTkArr;
  isvar: ParamVarArr;
  needs_copy: ParamVarArr;
  param_llvm_types: ADRMEM;
  i: INTEGER32;
  ret_tk: INTEGER;
  ret_llvm_ty, fnty, fn, entry_bb2: ADRMEM;
  param_val, palloca, ret_load: ADRMEM;
  existing: INTEGER32;
  ridx: INTEGER32;
  has_block_body: BOOLEAN;
  is_c, is_exported_entry, is_vararg: BOOLEAN;
  vararg_flag: INTEGER32;
  agg_llvm_ty, byval_attr, align_attr: ADRMEM;
  llvm_idx, n_llvm: INTEGER32;
  agg_class, n_pieces, eb: INTEGER;
  piece_kind: SysVPieceArr;
  piece_bytes: SysVPieceSzArr;
  cstruct_ty, cptr: ADRMEM;
  ret_class, ret_npieces: INTEGER;
  ret_pk: SysVPieceArr;
  ret_pb: SysVPieceSzArr;
  sret_attr, noalias_attr: ADRMEM;
  prev_n: INTEGER32;
  sig_ok: BOOLEAN;
BEGIN
  name := GetStr(decl, 'name');
  body_blk := GetObj(decl, 'body');
  has_block_body := NodeType(body_blk) = 'Block';
  { IsCForeignDecl(decl) reflects only THIS decl node's own attributes/
    directive -- a FORWARD-declared [C] EXTERN's later real definition (the
    existing<>0 branch below) may not repeat EXTERN/[C] on the body-bearing
    decl, so the routine table's own is_c (set once, at first declaration)
    is the source of truth once ridx is known; see below. }
  is_c := IsCForeignDecl(decl);
  { [VARARGS] only means anything across the C ABI, and (like is_c) the
    routine table's own copy is the source of truth once ridx is known. }
  is_vararg := is_c AND IsVarargsDecl(decl);
  is_exported_entry := GetBool(decl, 'is_exported_entry');

  existing := LookupRoutine(name);
  IF existing <> 0 THEN
  BEGIN
    { A prior FORWARD (or, degenerately, EXTERN) placeholder for this same
      name -- reuse its already-declared LLVM function/type rather than
      calling LLVMAddFunction again (which would just silently uniquify the
      name into a second, wrong function). A second *definition* is still an
      error; a second body-less declaration is not. A unit implementation
      must re-state, as a FORWARD, any routine its own INTERFACE already
      declared and whose definition it uses before reaching it -- an
      interface entry does not itself forward-declare, so the mutually
      recursive routines of a lowering unit have no other way to compile.
      That FORWARD lands here against the interface's own placeholder, and
      is a no-op rather than a redeclaration. Matches the reference. }
    IF routines[existing].has_body THEN
      AbortWith2('codegen: duplicate routine declaration: ', name);
    { EXTERN promises the body lives elsewhere, so this is not a placeholder
      awaiting completion -- FORWARD is the directive for that. The
      typechecker rejects this first and is the diagnostic users see; this
      guard keeps the stage from being silently permissive when driven
      directly, the same belt-and-braces the duplicate check above is. }
    IF routines[existing].is_extern THEN
      IF has_block_body THEN
        AbortWith2('codegen: EXTERN routine cannot be defined here (use FORWARD): ', name);
    ridx := existing;
    fn := routines[ridx].fn;
    fnty := routines[ridx].fnty;
    ret_tk := routines[ridx].ret_tk;
    { A FORWARD-declared PROCEDURE (not FUNCTION) stores ret_tk as
      TK_UNKNOWN, matching the non-forward branch below -- LLVMTypeForTk has
      no case for TK_UNKNOWN, so it must not be called for a void routine. }
    IF is_func THEN ret_llvm_ty := LLVMTypeForTk(ret_tk)
    ELSE ret_llvm_ty := voidty;
    { The reused fn/fnty carry the FIRST declaration's parameter shape, but
      everything below -- the entry-block allocas, the byval/align attribute
      attachment -- reads the arrays FlattenParams fills from THIS decl. The
      two agreeing is a load-bearing assumption, not something the LLVM side
      re-checks: a disagreeing pair silently lowers a body whose allocas and
      attributes do not match the function type it is being emitted into.
      Every redeclaration in this dialect restates the whole heading (the
      parser has no param-less repeat form -- ParseFuncDecl even requires
      the `: type`), so demanding agreement costs a conforming program
      nothing. ret_tk stays the table's; it is compared, not overwritten. }
    prev_n := routines[ridx].nparams;
    params_arr := GetObj(decl, 'params');
    FlattenParams(params_arr, n, names, tks, isvar, needs_copy);
    sig_ok := n = prev_n;
    IF sig_ok THEN
      FOR i := 1 TO n DO
      BEGIN
        IF tks[i] <> routines[ridx].param_tk[i] THEN sig_ok := FALSE;
        IF isvar[i] <> routines[ridx].param_is_var[i] THEN sig_ok := FALSE;
        IF needs_copy[i] <> routines[ridx].param_needs_copy[i] THEN sig_ok := FALSE;
      END;
    IF is_func THEN
      IF ResolveTypeExpr(GetObj(decl, 'return_type')) <> ret_tk THEN sig_ok := FALSE;
    IF NOT sig_ok THEN
      AbortWith2('codegen: redeclaration does not match the earlier declaration: ', name);
    routines[ridx].has_body := has_block_body; { still a placeholder when
      this pass is itself another body-less declaration -- see above. }
    is_c := routines[ridx].is_c; { source of truth once ridx is known -- see note above }
    is_vararg := routines[ridx].is_vararg; { likewise }
    { The already-built fnty is reused verbatim here, so it must already
      reflect the same classification recomputed below -- true as long as
      the placeholder that first declared this name (the fresh-declaration
      ELSE branch, whether reached as a genuine FORWARD or as this same
      branch's own first pass) applied the identical is_func/ret_tk-driven
      classification, which it always does; ClassifyAggregate/FuncRetAggClass
      are pure functions of ret_tk, so declaration and reuse can never
      disagree (same idiom as the parameter side). A plain-Pascal FUNCTION
      forward-declared through a spliced INTERFACE UNIT (e.g. jsonutil's
      Str255-returning routines) legitimately reaches this path with an
      aggregate return and a real body -- that is the normal case, not an
      error. A [C] EXTERN aggregate-returning FUNCTION reaching here is
      different: EXTERN promises the body lives elsewhere, so a real body
      under the same name is a self-contradictory program, not a shape this
      compiler can lower -- refuse it loudly rather than emit a body against
      an EXTERN declaration. }
    ret_class := 0;
    IF is_func THEN
      IF IsAggregateTk(ret_tk) THEN
      BEGIN
        IF has_block_body AND is_c THEN
          AbortWith2('codegen: [C] EXTERN routine with an aggregate return cannot be defined here: ', name)
        ELSE
        BEGIN
          ClassifyAggregate(ret_tk, ret_class, ret_npieces, ret_pk, ret_pb);
          IF ret_class = SYSV_CLASS_MEMORY THEN ret_llvm_ty := voidty
          ELSE ret_llvm_ty := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
        END;
      END;
  END
  ELSE
  BEGIN
    params_arr := GetObj(decl, 'params');
    FlattenParams(params_arr, n, names, tks, isvar, needs_copy);

    IF is_func THEN
    BEGIN
      ret_tk := ResolveTypeExpr(GetObj(decl, 'return_type'));
      ret_llvm_ty := LLVMTypeForTk(ret_tk);
    END
    ELSE
    BEGIN
      ret_tk := TK_UNKNOWN;
      ret_llvm_ty := voidty;
    END;

    { The return has to be classified BEFORE the parameter list is built: a
      FUNCTION (plain Pascal or [C] FOREIGN alike) returning a MEMORY-class
      aggregate returns void and takes a hidden pointer to the caller's
      result storage as its FIRST LLVM parameter, shifting every real
      parameter's LLVM index by one. A COERCED-class aggregate return needs
      no hidden pointer -- it comes back in one or two registers, i.e. as a
      plain non-aggregate LLVM return type -- so it only rewrites
      ret_llvm_ty. Everything else (PROCEDUREs and scalar returns) is
      untouched. }
    ret_class := 0;
    IF is_func THEN
      IF IsAggregateTk(ret_tk) THEN
      BEGIN
        ClassifyAggregate(ret_tk, ret_class, ret_npieces, ret_pk, ret_pb);
        IF ret_class = SYSV_CLASS_MEMORY THEN ret_llvm_ty := voidty
        ELSE ret_llvm_ty := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
      END;

    { A COERCED-class [C] aggregate parameter is passed as one LLVM
      parameter per eightbyte (at most two), so the LLVM parameter list can
      be longer than the Pascal one -- llvm_idx below is the running LLVM
      parameter index, and n_llvm the final count. Two slots per Pascal
      parameter is the worst case, plus one for an sret hidden pointer
      (which also seeds llvm_idx at 1 instead of 0). }
    param_llvm_types := AllocPtrArray(n * 2 + 1);
    llvm_idx := 0;
    IF ret_class = SYSV_CLASS_MEMORY THEN
    BEGIN
      SetPtrArrayElem(param_llvm_types, 0, LLVMPointerType(LLVMTypeForTk(ret_tk), 0));
      llvm_idx := 1;
    END;
    FOR i := 1 TO n DO
    BEGIN
      IF isvar[i] THEN
      BEGIN
        SetPtrArrayElem(param_llvm_types, llvm_idx, LLVMPointerType(LLVMTypeForTk(tks[i]), 0));
        llvm_idx := llvm_idx + 1;
      END
      ELSE IF needs_copy[i] THEN
      BEGIN
        { Value-mode aggregate param (ARRAY/RECORD/LSTRING/STRING), plain
          Pascal and [C] FOREIGN alike -- explicit SysV classification,
          matching c_abi.py: MEMORY class (>16 bytes, or 0) is a pointer to
          a private per-call copy, with the byval(ty)/align attributes
          attached below once `fn` exists; COERCED class (<=16 bytes, all
          eightbytes INTEGER/SSE) is flattened into its register pieces
          instead, and gets no parameter attribute at all. }
        ClassifyAggregate(tks[i], agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
        BEGIN
          SetPtrArrayElem(param_llvm_types, llvm_idx, LLVMPointerType(LLVMTypeForTk(tks[i]), 0));
          llvm_idx := llvm_idx + 1;
        END
        ELSE
          FOR eb := 1 TO n_pieces DO
          BEGIN
            SetPtrArrayElem(param_llvm_types, llvm_idx,
                            SysVPieceLLVMType(piece_kind[eb], piece_bytes[eb]));
            llvm_idx := llvm_idx + 1;
          END;
      END
      ELSE
      BEGIN
        SetPtrArrayElem(param_llvm_types, llvm_idx, LLVMTypeForTk(tks[i]));
        llvm_idx := llvm_idx + 1;
      END;
    END;
    n_llvm := llvm_idx;

    { A handful of C runtime/libm functions (malloc, free, printf, ...) are
      already declared in the module by the init block above, for this
      compiler's OWN internal codegen (NEW/DISPOSE, WRITE/WRITELN, string
      builtins, SQRT/SIN/...) to call directly via their fn/fnty globals --
      independently of whatever the source program's own [C]; EXTERN
      declares under the same name (e.g. jsonutil.pas/lexer.pas both declare
      `EXTERN malloc` for their own use). Reuse that existing LLVM function
      instead of calling LLVMAddFunction again: a second LLVMAddFunction for
      an already-declared name doesn't error, it silently uniquifies to
      `malloc.1`/`free.2`/etc, which then has no real symbol to link against
      -- found only by actually clang-linking self-hosted output, since
      LLVMVerifyModule accepts the (internally consistent, if wrong) IR. }
    IF name = 'malloc' THEN BEGIN fn := malloc_fn; fnty := malloc_fnty; END
    ELSE IF name = 'free' THEN BEGIN fn := free_fn; fnty := free_fnty; END
    ELSE IF name = 'memmove' THEN BEGIN fn := memmove_fn; fnty := memmove_fnty; END
    ELSE IF name = 'memcmp' THEN BEGIN fn := memcmp_fn; fnty := memcmp_fnty; END
    ELSE IF name = 'positn' THEN BEGIN fn := positn_fn; fnty := positn_fnty; END
    ELSE IF name = 'scaneq' THEN BEGIN fn := scaneq_fn; fnty := scaneq_fnty; END
    ELSE IF name = 'scanne' THEN BEGIN fn := scanne_fn; fnty := scanne_fnty; END
    ELSE IF name = 'encode_value' THEN BEGIN fn := encode_fn; fnty := encode_fnty; END
    ELSE IF name = 'decode_value' THEN BEGIN fn := decode_fn; fnty := decode_fnty; END
    ELSE IF name = 'sqrt' THEN BEGIN fn := sqrt_fn; fnty := sqrt_fnty; END
    ELSE IF name = 'sin' THEN BEGIN fn := sin_fn; fnty := sin_fnty; END
    ELSE IF name = 'cos' THEN BEGIN fn := cos_fn; fnty := cos_fnty; END
    ELSE IF name = 'log' THEN BEGIN fn := log_fn; fnty := log_fnty; END
    ELSE IF name = 'exp' THEN BEGIN fn := exp_fn; fnty := exp_fnty; END
    ELSE IF name = 'atan' THEN BEGIN fn := atan_fn; fnty := atan_fnty; END
    ELSE IF name = 'printf' THEN BEGIN fn := printf_fn; fnty := printf_fnty; END
    ELSE
    BEGIN
      { A [VARARGS] [C] routine gets a genuinely variadic LLVM function type
        (trailing is_var_arg = 1), the same shape the printf/write_fmt
        declarations in the init block above already use. }
      IF is_vararg THEN vararg_flag := 1 ELSE vararg_flag := 0;
      fnty := LLVMFunctionType(ret_llvm_ty, param_llvm_types, n_llvm, vararg_flag);
      fn := LLVMAddFunction(modl, MakeCStr(name), fnty);
    END;

    { Reusing an init-declared function means the LLVM signature that call
      sites must satisfy is the init block's, not the source declaration's.
      Where the two disagree the recorded parameter types have to follow the
      real function, or CoerceForAssign marshals every actual to the source
      width and LLVM rejects the call. `malloc(size: CINT)` is the live case:
      the init block declares C's size_t (i64) on this LP64 host, while every
      self-hosting source spells the parameter CINT (i32). }
    IF (name = 'malloc') AND (n = 1) THEN tks[1] := TK_INTEGER64;

    { Register the routine before codegen'ing its body -- direct
      self-recursion (Fact calling Fact) needs the routine table entry to
      already exist when the body's own FuncCall/ProcCallStmt nodes resolve
      it. Mutual recursion (A calls B declared later) is out of scope, same
      as it would be without a FORWARD declaration in standard Pascal. }
    IF nroutines >= MAX_ROUTINES THEN AbortWith('codegen: too many routines');
    nroutines := nroutines + 1;
    ridx := nroutines;
    routines[ridx].name := name;
    routines[ridx].is_func := is_func;
    routines[ridx].fn := fn;
    routines[ridx].fnty := fnty;
    routines[ridx].ret_tk := ret_tk;
    routines[ridx].nparams := n;
    FOR i := 1 TO n DO
    BEGIN
      routines[ridx].param_tk[i] := tks[i];
      routines[ridx].param_is_var[i] := isvar[i];
      routines[ridx].param_needs_copy[i] := needs_copy[i];
    END;
    routines[ridx].has_body := has_block_body;
    routines[ridx].is_c := is_c;
    routines[ridx].is_extern := IsExternDirectiveDecl(decl) OR IsCForeignDecl(decl);
    routines[ridx].is_vararg := is_vararg;

    { Attach byval(ty)/align (and sret(ty)/noalias/align for a MEMORY-class
      return) at the DECLARATION side too (not just the call site below) --
      LLVM attaches parameter attributes to both the function
      definition/declaration and each call site; clang emits both, and only
      doing one leaves the IR inconsistent with what a real C compiler
      produces for the same signature (verification step 7). Applies to
      plain-Pascal routines exactly like [C] FOREIGN ones, via the same
      FuncRetAggClass/ClassifyAggregate calls both sides use. Attribute
      index is 1-based over LLVM parameters (0 is the return), which is why
      it is walked with llvm_idx rather than the Pascal
      parameter index: a COERCED aggregate parameter occupies one slot per
      eightbyte and carries no attribute of its own -- byval and align
      describe a pointer to memory, which a register-passed aggregate never
      has. }
    llvm_idx := 0;
    IF ret_class = SYSV_CLASS_MEMORY THEN
    BEGIN
      { The hidden result pointer is LLVM parameter 0, i.e. attribute
        index 1. `sret(ty)` names the pointee type the callee writes the
        result through; `noalias` is the SysV promise that this storage is
        the caller's fresh result temp and overlaps nothing else the call
        can see; `align` matches what the byval path attaches, and what
        the reference records alongside its own sret attributes. }
      agg_llvm_ty := LLVMTypeForTk(ret_tk);
      sret_attr := LLVMCreateTypeAttribute(ctx, sret_kind_id, agg_llvm_ty);
      align_attr := LLVMCreateEnumAttribute(ctx, align_kind_id, SysVByvalAlign(ret_tk));
      LLVMAddAttributeAtIndex(fn, 1, sret_attr);
      LLVMAddAttributeAtIndex(fn, 1, align_attr);
      IF noalias_kind_id <> 0 THEN
      BEGIN
        noalias_attr := LLVMCreateEnumAttribute(ctx, noalias_kind_id, 0);
        LLVMAddAttributeAtIndex(fn, 1, noalias_attr);
      END;
      llvm_idx := 1;
    END;
    FOR i := 1 TO n DO
    BEGIN
      IF needs_copy[i] THEN
      BEGIN
        ClassifyAggregate(tks[i], agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
        BEGIN
          agg_llvm_ty := LLVMTypeForTk(tks[i]);
          byval_attr := LLVMCreateTypeAttribute(ctx, byval_kind_id, agg_llvm_ty);
          align_attr := LLVMCreateEnumAttribute(ctx, align_kind_id, SysVByvalAlign(tks[i]));
          LLVMAddAttributeAtIndex(fn, llvm_idx + 1, byval_attr);
          LLVMAddAttributeAtIndex(fn, llvm_idx + 1, align_attr);
          llvm_idx := llvm_idx + 1;
        END
        ELSE
          llvm_idx := llvm_idx + n_pieces;
      END
      ELSE
        llvm_idx := llvm_idx + 1;
    END;
  END;

  { An exported DEVICE PROCEDURE becomes a launchable NVPTX entry. The
    interface placeholder has no flag; the implementation declaration does. }
  IF is_nvptx_device AND is_exported_entry THEN
  BEGIN
    LLVMSetFunctionCallConv(fn, 71); { LLVMCCallConv::PTX_Kernel }
    ApplyKernelParamAttrs(decl, fn, n, tks);
    ApplyLaunchBoundAttrs(decl, fn);
  END;

  { EXTERN/FORWARD placeholder: the function is declared (or was already,
    on a prior FORWARD pass) and registered, but there is no Block body to
    codegen yet -- nothing further to do until (if ever) a real definition
    for this same name arrives. Wrapped in an IF rather than a bare EXIT,
    matching CodegenBinOp's own note: this dialect has no EXIT
    statement/procedure at all, so an early return has to be an IF guard. }
  IF has_block_body THEN
  BEGIN
    entry_bb2 := LLVMAppendBasicBlockInContext(ctx, fn, MakeCStr('entry'));
    LLVMPositionBuilderAtEnd(builder, entry_bb2);
    cur_fn := fn;
    PushScope;
    in_local_scope := TRUE;

    IF is_func THEN
    BEGIN
      cur_func_name := name;
      cur_func_ret_tk := ret_tk;
      IF ret_class = SYSV_CLASS_MEMORY THEN
        { The hidden sret pointer (LLVM parameter 0) already points at the
          caller's own result storage -- use it directly, exactly like a
          byval parameter uses its incoming pointer directly, so every
          RETURN/function-name-assignment site (which always addresses
          cur_func_ret_slot via cur_func_ret_tk, the real Pascal type, not
          ret_llvm_ty) stores straight into the caller's buffer with no
          extra copy, and the epilogue below needs no load/ret of the LLVM
          return type at all (which is void here). }
        cur_func_ret_slot := LLVMGetParam(fn, 0)
      ELSE IF ret_class = SYSV_CLASS_COERCED THEN
      BEGIN
        { Real aggregate-typed storage, over-aligned to a full eightbyte so
          the epilogue's coerced-type reload can view it as the (possibly
          wider) coerced register layout -- mirrors the COERCED parameter
          prologue's own over-aligned slot. }
        cur_func_ret_slot := EntryAlloca(LLVMTypeForTk(ret_tk), 'return_value');
        LLVMSetAlignment(cur_func_ret_slot, 8);
      END
      ELSE
        cur_func_ret_slot := EntryAlloca(ret_llvm_ty, 'return_value');
      IF (ret_tk = TK_REAL) OR (ret_tk = TK_REAL32) THEN LLVMBuildStore(builder, LLVMConstReal(LLVMTypeForTk(ret_tk), 0.0), cur_func_ret_slot)
      ELSE IF (ret_tk = TK_BOOLEAN) OR (ret_tk = TK_CHAR) OR IsIntegerFamilyTk(ret_tk) THEN
        LLVMBuildStore(builder, LLVMConstInt(LLVMTypeForTk(ret_tk), 0, 0), cur_func_ret_slot)
      ELSE
        { ADRMEM/POINTER, or an aggregate (LSTRING/STRING/ARRAY/RECORD)
          return type -- neither fits LLVMConstInt (not an integer LLVM
          type), so zero it via LLVMConstNull instead, matching the
          reference's own all-zero default-return initialization. Typed by
          the real Pascal return type (cur_func_ret_slot's own storage
          type), not ret_llvm_ty, which for a MEMORY/COERCED aggregate
          return no longer matches that storage's type. }
        LLVMBuildStore(builder, LLVMConstNull(LLVMTypeForTk(ret_tk)), cur_func_ret_slot);
    END
    ELSE
      cur_func_name := '';

    { llvm_idx is the running LLVM parameter index: it starts at 1 instead
      of 0 when a hidden sret result pointer occupies LLVM parameter 0 (see
      the matching seed in the signature-building and attribute-attachment
      code above), and from there only tracks the Pascal parameter index
      while no COERCED aggregate parameter has been seen, since such a
      parameter arrives as one LLVM parameter per eightbyte (at most two). }
    IF ret_class = SYSV_CLASS_MEMORY THEN llvm_idx := 1 ELSE llvm_idx := 0;
    FOR i := 1 TO n DO
    BEGIN
      param_val := LLVMGetParam(fn, llvm_idx);
      llvm_idx := llvm_idx + 1;
      IF isvar[i] THEN
        palloca := param_val { the incoming pointer already IS the storage }
      ELSE IF needs_copy[i] THEN
      BEGIN
        { Value-mode aggregate param, plain Pascal and [C] FOREIGN alike. }
        ClassifyAggregate(tks[i], agg_class, n_pieces, piece_kind, piece_bytes);
        IF agg_class = SYSV_CLASS_MEMORY THEN
          { SysV byval: the incoming pointer already refers to a private
            per-call copy the caller made (see the byval caller-side temp in
            CodegenCallCommon) -- use it directly as storage, exactly like
            isvar above, no further copy needed. }
          palloca := param_val
        ELSE
        BEGIN
          { COERCED class: the aggregate arrived in one or two registers.
            Reverse the caller's flattening -- give it real storage of the
            aggregate's own type and write each incoming piece back through
            the coerced piece struct laid over that storage, so the rest of
            codegen sees an ordinary aggregate local. The slot is
            over-aligned to a full eightbyte so every piece store is
            naturally aligned even when the aggregate's own alignment is
            smaller (e.g. a two-INTEGER32 record, align 4, written as one
            i64). }
          palloca := EntryAlloca(LLVMTypeForTk(tks[i]), names[i]);
          LLVMSetAlignment(palloca, 8);
          cstruct_ty := SysVCoercedStructType(n_pieces, piece_kind, piece_bytes);
          cptr := LLVMBuildBitCast(builder, palloca, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
          FOR eb := 1 TO n_pieces DO
          BEGIN
            { param_val already holds the first piece; the rest follow it
              in consecutive LLVM parameters. }
            IF eb > 1 THEN
            BEGIN
              param_val := LLVMGetParam(fn, llvm_idx);
              llvm_idx := llvm_idx + 1;
            END;
            LLVMBuildStore(builder, param_val, SysVCoercedPiecePtr(cptr, cstruct_ty, eb));
          END;
        END;
      END
      ELSE
      BEGIN
        palloca := EntryAlloca(LLVMTypeForTk(tks[i]), names[i]);
        LLVMBuildStore(builder, param_val, palloca);
      END;
      IF nsymbols >= MAX_SYMBOLS THEN AbortWith('codegen: too many symbols');
      nsymbols := nsymbols + 1;
      symbols[nsymbols].name := names[i];
      symbols[nsymbols].tk := tks[i];
      symbols[nsymbols].llvm_val := palloca;
    END;

    CodegenDeclList(GetObj(body_blk, 'decls'));
    SetupFunctionLabels(GetObj(body_blk, 'body'));
    CodegenStmtArray(GetObj(body_blk, 'body'));

    IF is_func THEN
    BEGIN
      IF ret_class = SYSV_CLASS_MEMORY THEN
        { Every RETURN/function-name-assignment already stored straight
          into the caller's sret buffer (cur_func_ret_slot IS that pointer)
          -- nothing left to load, and this function's LLVM return type is
          void. }
        LLVMBuildRetVoid(builder)
      ELSE IF ret_class = SYSV_CLASS_COERCED THEN
      BEGIN
        { Reverse of the COERCED parameter prologue: view the (over-aligned)
          aggregate storage as the coerced register layout and read that
          layout back out as one value, ready to `ret` in one or two
          registers -- mirrors the caller side's own coerced-return
          reconstruction (CodegenCallCommon) in the opposite direction. }
        cstruct_ty := SysVCoercedRetType(ret_npieces, ret_pk, ret_pb);
        cptr := LLVMBuildBitCast(builder, cur_func_ret_slot, LLVMPointerType(cstruct_ty, 0), MakeCStr(''));
        ret_load := LLVMBuildLoad2(builder, cstruct_ty, cptr, MakeCStr(''));
        LLVMSetAlignment(ret_load, 8);
        ret_load := LLVMBuildRet(builder, ret_load);
      END
      ELSE
      BEGIN
        ret_load := LLVMBuildLoad2(builder, ret_llvm_ty, cur_func_ret_slot, MakeCStr(''));
        ret_load := LLVMBuildRet(builder, ret_load);
      END;
    END
    ELSE
      LLVMBuildRetVoid(builder);

    PopScope;
    in_local_scope := FALSE;
    cur_func_name := '';
    cur_fn := main_fn;
    LLVMPositionBuilderAtEnd(builder, entry_bb);
  END;
END;

FUNCTION IsExternDirectiveDecl(decl: ADRMEM): BOOLEAN;
{ True when this declaration carries the EXTERN/EXTERNAL directive in the
  slot a block would occupy -- as opposed to the [C]/[EXTERN] attribute form
  IsCForeignDecl looks at. }
VAR
  directive: Str255;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  directive := GetStr(decl, 'directive');
  IF directive = 'EXTERN' THEN found := TRUE;
  IF directive = 'EXTERNAL' THEN found := TRUE;
  IsExternDirectiveDecl := found;
END;

PROCEDURE CodegenRoutineDecl(decl: ADRMEM; is_func: BOOLEAN);
{ The 1981 manual's mechanism for a UNIT whose IMPLEMENTATION does not supply
  every body itself: "any implementation section that does not implement all
  interface procedures and functions must declare those not implemented with
  the EXTERN directive at the start of the implementation" (IBM Pascal, Aug
  1981, Units chapter), which is how one INTERFACE is split across several
  IMPLEMENTATIONs, or shared with assembly / another language.

  Such a redeclaration names a routine the spliced INTERFACE header has
  already declared, and carries no body of its own, so the inner routine
  would reject it as a duplicate. It is a no-op here instead: the placeholder
  the interface created is already exactly the LLVM declaration this EXTERN
  asks for, and re-lowering it would re-apply the SysV byval/sret parameter
  attributes to the same function a second time.

  Deliberately narrow -- only a body-less EXTERN/EXTERNAL directive against
  an existing body-less placeholder is absorbed. A second real definition, or
  a bare bodyless redeclaration with no directive, still aborts in the inner
  routine, and the typechecker has already checked this declaration's
  signature against the interface's (ValidateRoutineExport). }
VAR
  existing: INTEGER32;
  absorb: BOOLEAN;
BEGIN
  absorb := FALSE;
  { Plain AND is not short-circuit in this dialect, so routines[existing] must
    not be indexed in the same expression that tests existing <> 0. }
  IF NodeType(GetObj(decl, 'body')) <> 'Block' THEN
    IF IsExternDirectiveDecl(decl) THEN
    BEGIN
      existing := LookupRoutine(GetStr(decl, 'name'));
      IF existing <> 0 THEN
        IF NOT routines[existing].has_body THEN absorb := TRUE;
    END;
  IF NOT absorb THEN CodegenRoutineDeclInner(decl, is_func);
END;

PROCEDURE CodegenTypeDecl(decl: ADRMEM);
VAR
  name: Str255;
  tid: INTEGER;
BEGIN
  name := GetStr(decl, 'name');
  IF LookupNamedType(name) <> 0 THEN
    AbortWith2('codegen: duplicate type declaration: ', name);
  tid := ResolveTypeExpr(GetObj(decl, 'type_expr'));
  IF tid < 5 THEN
    AbortWith2('codegen: TYPE cannot alias a bare scalar name: ', name);
  types[tid].name := name;
END;

PROCEDURE CodegenConstDecl(decl: ADRMEM);
{ Every CONST this file's own native sources declare is a plain (optionally
  MINUS-negated) integer or REAL literal -- this compile-time-folds and
  remembers the value in `const_tbl`, mirroring the Python reference's
  eval_const_expr/self.constants side table rather than emitting a real LLVM
  global. }
VAR
  name: Str255;
  val_node: ADRMEM;
BEGIN
  name := GetStr(decl, 'name');
  IF LookupConst(name) <> 0 THEN
    AbortWith2('codegen: duplicate const declaration: ', name);
  val_node := GetObj(decl, 'value');
  nconsts := nconsts + 1;
  const_tbl[nconsts].name := name;
  IF NodeType(val_node) = 'RealLiteral' THEN
  BEGIN
    const_tbl[nconsts].is_real := TRUE;
    const_tbl[nconsts].rval := GetReal(val_node, 'value');
  END
  ELSE IF (NodeType(val_node) = 'UnaryOp') AND (GetStr(val_node, 'op') = 'MINUS')
      AND (NodeType(GetObj(val_node, 'operand')) = 'RealLiteral') THEN
  BEGIN
    const_tbl[nconsts].is_real := TRUE;
    const_tbl[nconsts].rval := 0.0 - GetReal(GetObj(val_node, 'operand'), 'value');
  END
  ELSE
  BEGIN
    const_tbl[nconsts].is_real := FALSE;
    const_tbl[nconsts].ival := IntLiteralValue(val_node);
  END;
END;

PROCEDURE CodegenDecl(decl: ADRMEM);
VAR
  nt: Str255;
BEGIN
  nt := NodeType(decl);
  IF nt = 'VarDecl' THEN CodegenVarDecl(decl)
  ELSE IF nt = 'TypeDecl' THEN CodegenTypeDecl(decl)
  ELSE IF nt = 'ConstDecl' THEN CodegenConstDecl(decl)
  ELSE IF nt = 'ProcDecl' THEN CodegenRoutineDecl(decl, FALSE)
  ELSE IF nt = 'FuncDecl' THEN CodegenRoutineDecl(decl, TRUE)
  ELSE IF nt = 'LabelDecl' THEN
    { No-op: every label's block was already allocated by SetupFunctionLabels
      from the actual LabelStmt occurrences in the body, independent of this
      declaration's text -- matches the Python reference's own LabelDecl
      handling (codegen/decls.py: emits no direct code). }
    BEGIN END
  ELSE
    AbortWith2('codegen: unhandled declaration kind: ', nt);
END;


BEGIN
END.
