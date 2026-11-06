{ Implementations for cg_util. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
IMPLEMENTATION OF cg_util;

CONST
  { The size from which LowerLargeAggregateCopies moves an aggregate with
    memmove/memcpy/memset instead of a first-class load and store. }
  LARGE_AGGREGATE_BYTES = 1024;

VAR
  expr_depth, stmt_depth: INTEGER;
  layout_line, layout_column: INTEGER32;
  { Up-level access (static links). frame_top routine bodies are being
    lowered, outermost first; frame 1 is a compiland-level routine. A frame's
    symbols are symbols[frame_sym_base + 1 ..]. A nested routine takes its
    parent frame's environment, an array of pointers built in the parent's
    entry block, as its hidden last parameter (frame_link). env_slot_*
    holds each frame's slots, MAX_ENV_SLOTS per frame. A capture caches,
    per frame, the pointer an up-level name resolves to in that routine
    (loaded before frame_anchor in its entry block); a captured symbol's
    llvm_val is swapped for it until the frame closes. }
  frame_top: INTEGER32;
  frame_fn, frame_link, frame_anchor, frame_env: ARRAY [1..MAX_FRAMES] OF ADRMEM;
  frame_name, frame_func_name: ARRAY [1..MAX_FRAMES] OF Str255;
  frame_sym_base, frame_nslots: ARRAY [1..MAX_FRAMES] OF INTEGER32;
  frame_ret_slot, frame_ret_state: ARRAY [1..MAX_FRAMES] OF ADRMEM;
  frame_ret_tk: ARRAY [1..MAX_FRAMES] OF INTEGER;
  env_slot_key: ARRAY [1..MAX_ENV_TOTAL] OF INTEGER32;
  env_slot_val: ARRAY [1..MAX_ENV_TOTAL] OF ADRMEM;
  ncaptures: INTEGER32;
  capture_frame, capture_owner, capture_key: ARRAY [1..MAX_CAPTURES] OF INTEGER32;
  capture_val, capture_old: ARRAY [1..MAX_CAPTURES] OF ADRMEM;
  capture_suspended: BOOLEAN; { TRUE while a pass only resolves names and
    emits no code through them (PrepareInitckLocals): no capture is made,
    so a rejected one is reported where the code uses it }

{ ============================== utilities ============================== }

PROCEDURE AbortWith(msg: Str255);
VAR
  res_c: CINT;
BEGIN
  EPrint(msg);
  exit(1);
END;

FUNCTION EntryAlloca(ty: ADRMEM; name: Str255): ADRMEM;
{ Every stack-slot alloca must live in the function's ENTRY block, not
  wherever `builder` currently happens to be positioned -- an alloca inside
  a loop body (or any block that runs more than once) executes AGAIN on
  every pass, growing the stack without ever popping until the function
  returns, not just once per function call the way a true local variable
  does. Found via a real bug this way: parser.pas's token-reading loop
  calls a helper with 15 string-literal arguments per iteration; each
  materialized-literal temp used a bare LLVMBuildAlloca at the call site
  (inside the loop body), so a several-thousand-token file blew the stack
  and segfaulted deep inside an unrelated later call. Temporarily
  repositions the builder to the entry block's first instruction (or its
  end, if it has none yet), builds the alloca there, then restores the
  builder to wherever it was -- safe to call from any block, including one
  that has already been terminated by a br/ret (callers positioned at
  entry itself, e.g. CodegenRoutineDecl's own param/return-slot allocas,
  are unaffected: repositioning to entry when already at entry is a
  no-op). }
VAR
  saved_bb, entry_bb, first_instr, res: ADRMEM;
BEGIN
  saved_bb := LLVMGetInsertBlock(builder);
  entry_bb := LLVMGetEntryBasicBlock(cur_fn);
  first_instr := LLVMGetFirstInstruction(entry_bb);
  IF first_instr = NIL THEN LLVMPositionBuilderAtEnd(builder, entry_bb)
  ELSE LLVMPositionBuilderBefore(builder, first_instr);
  res := LLVMBuildAlloca(builder, ty, MakeCStr(name));
  LLVMPositionBuilderAtEnd(builder, saved_bb);
  EntryAlloca := res;
END;

FUNCTION GetObjOrNil(obj: ADRMEM; key: Str255): ADRMEM;
{ jsonutil's GetObj returns cJSON's own pointer for a key whose JSON value
  is literally `null` -- a real, non-NULL cJSON node of type cJSON_NULL, not
  a NIL/absent-key sentinel. Optional AST fields (e.g. IfStmt's
  else_branch) are serialized as `null` when absent, so a bare "GetObj(...)
  <> NIL" check treats "no else" the same as "else present" and then fails
  trying to codegen a nonexistent statement. Fold both "absent" and
  "present but null" down to NIL here so callers can use one check. }
VAR
  v: ADRMEM;
BEGIN
  v := GetObj(obj, key);
  IF (v <> NIL) AND (cJSON_IsNull(v) <> 0) THEN v := NIL;
  GetObjOrNil := v;
END;

FUNCTION IntToStr255(n: INTEGER32): Str255;
{ Decimal text of n, for numeric GOTO labels (which arrive from the parser
  as JSON numbers while the `labels` table's lookup key is text) and for
  numbers in diagnostics. Builds digits into `tmp` least-significant-first via direct Str255
  indexing (the same s[0]=length-byte convention CStrToStr255 uses), then
  reverses into `res` -- no CONCAT needed, this is plain char-array work. }
VAR
  neg: BOOLEAN;
  v: INTEGER64; { |n| of the INTEGER32 minimum has no INTEGER32 value }
  digit: INTEGER64;
  tmp, res: Str255;
  len, i, out_i: INTEGER;
BEGIN
  neg := n < 0;
  v := n;
  IF neg THEN v := -v;
  len := 0;
  IF v = 0 THEN
  BEGIN
    len := 1;
    tmp[1] := '0';
  END
  ELSE
    WHILE v > 0 DO
    BEGIN
      len := len + 1;
      digit := ORD('0') + (v MOD 10);
      tmp[len] := CHR(RETYPE(INTEGER, digit));
      v := v DIV 10;
    END;
  out_i := 0;
  IF neg THEN
  BEGIN
    out_i := out_i + 1;
    res[out_i] := '-';
  END;
  FOR i := len DOWNTO 1 DO
  BEGIN
    out_i := out_i + 1;
    res[out_i] := tmp[i];
  END;
  res[0] := CHR(out_i);
  IntToStr255 := res;
END;

PROCEDURE AbortWith2(prefix: Str255; suffix: Str255);
{ prefix followed by suffix (usually an identifier), whose middle is
  elided when both do not fit a Str255. }
VAR
  msg: Str255;
BEGIN
  msg := prefix;
  AppendText(msg, CgElide(suffix, 255 - ORD(prefix[0])));
  AbortWith(msg);
END;

{ ======================== layout size limits ==========================

  Type layout bookkeeping (field offsets, sizes, strides, INITCK leaf
  counts) is INTEGER32, and the compiler runs with MATHCK on: an offset sum
  that left that range would stop the compile with a MATHCK trap inside
  codegen instead of a diagnostic. Every such sum is formed in INTEGER64
  and passed through LayoutBytes, which rejects a layout above 2147483647
  bytes. The diagnostic names the declaration or statement whose lowering
  needed the layout: CodegenDecl and CodegenStmt record it with
  EnterLayoutSite. }

PROCEDURE AbortAtLayoutSite(msg: Str255);
VAR
  suffix: Str255;
BEGIN
  IF (layout_line > 0) AND (layout_column > 0) THEN
  BEGIN
    suffix := ' at line ';
    AppendText(suffix, IntToStr255(layout_line));
    AppendText(suffix, ' column ');
    AppendText(suffix, IntToStr255(layout_column));
    msg := CgElide(msg, 255 - ORD(suffix[0]));
    AppendText(msg, suffix);
  END;
  AbortWith(msg);
END;

PROCEDURE LayoutTooLarge;
BEGIN
  AbortAtLayoutSite('codegen: type layout exceeds the supported 2147483647-byte size');
END;

FUNCTION LayoutBytes(wide: INTEGER64): INTEGER32;
BEGIN
  IF (wide > 2147483647) OR (wide < 0) THEN
  BEGIN
    LayoutTooLarge;
    LayoutBytes := 0;
  END
  ELSE
    LayoutBytes := RETYPE(INTEGER32, wide);
END;

PROCEDURE EnterLayoutSite(node: ADRMEM; VAR saved_line, saved_column: INTEGER32);
VAR
  location: ADRMEM;
BEGIN
  saved_line := layout_line;
  saved_column := layout_column;
  location := GetObjOrNil(node, 'location');
  IF location <> NIL THEN
  BEGIN
    layout_line := GetInt(location, 'line');
    layout_column := GetInt(location, 'column');
  END;
END;

PROCEDURE LeaveLayoutSite(saved_line, saved_column: INTEGER32);
BEGIN
  layout_line := saved_line;
  layout_column := saved_column;
END;

{ ===================== recursion-depth ceilings ======================

  AST lowering recurses over the tree, so its stack use is bounded only by
  the depth of the AST -- and the AST's depth is bounded only by the source.
  Without a ceiling the only limit is the OS stack, and exceeding it is a
  segfault with no diagnostic, which is what used to make callers of this
  stage wrap it in `ulimit -s unlimited`.

  The parser applies the same ceilings, at the same values, to the same two
  cycles (CodegenExpr's operand walk and CodegenStmt's nested-statement
  walk), so an AST that reaches codegen has already been accepted at these
  depths -- these guards catch a hand-built or third-party AST rather than
  anything the native front end can produce. See parser.pas's fuller note on
  where the numbers come from and why bounding this is period-correct
  ("Expression too complex", Aug-1981 manual, appendix A). The reference
  compiler enforces the same ceilings on its own AST walks, for the same
  reason: it too can be handed an AST from stdin. }

PROCEDURE EnterExprLevel;
BEGIN
  expr_depth := expr_depth + 1;
  IF expr_depth > MAX_EXPR_DEPTH THEN
    AbortWith('codegen: expression too complex (nesting deeper than 64); try breaking it up with intermediate value assigns');
END;

PROCEDURE LeaveExprLevel;
BEGIN
  expr_depth := expr_depth - 1;
END;

PROCEDURE EnterStmtLevel;
BEGIN
  stmt_depth := stmt_depth + 1;
  IF stmt_depth > MAX_STMT_DEPTH THEN
    AbortWith('codegen: statements nested too deeply (deeper than 256); try splitting the routine up');
END;

PROCEDURE LeaveStmtLevel;
BEGIN
  stmt_depth := stmt_depth - 1;
END;

FUNCTION DecodeStringLiteral(raw: Str255): Str255;
{ raw is the token lexeme convention: outer single quotes kept, embedded
  quote pairs ('') collapsed to a single quote -- the inverse of lexer.py's
  "'" + value.replace("'", "''") + "'". }
VAR
  res: Str255;
  len, i, outlen: INTEGER;
  is_escaped_quote: BOOLEAN;
BEGIN
  len := ORD(raw[0]);
  outlen := 0;
  IF len < 2 THEN AbortWith('codegen: malformed string literal');
  i := 2;
  WHILE i <= len - 1 DO
  BEGIN
    { Plain AND is not short-circuit in this dialect -- guard the i+1
      bounds check with a nested IF instead of chaining it into the same
      AND expression as the raw[i + 1] read, or that read would still
      execute even when i + 1 is out of range. }
    is_escaped_quote := FALSE;
    IF (raw[i] = '''') AND (i + 1 <= len - 1) THEN
      is_escaped_quote := raw[i + 1] = '''';
    IF is_escaped_quote THEN
    BEGIN
      outlen := outlen + 1;
      res[outlen] := '''';
      i := i + 2;
    END
    ELSE
    BEGIN
      outlen := outlen + 1;
      res[outlen] := raw[i];
      i := i + 1;
    END;
  END;
  res[0] := CHR(outlen);
  DecodeStringLiteral := res;
END;

PROCEDURE AppendChar(VAR s: Str255; ch: CHAR);
VAR
  len: INTEGER;
BEGIN
  len := ORD(s[0]);
  IF len < 255 THEN
  BEGIN
    s[len + 1] := ch;
    s[0] := CHR(len + 1);
  END;
END;

FUNCTION UpperStr(s: Str255): Str255;
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

{ ======================= symbol and routine lookup ======================== }
{ These live here rather than in cg_symbols beside the rest of the symbol and
  routine tables because cg_types needs UserRoutineShadows and LookupSym --
  see IsIntLiteralLike -- and sits below cg_symbols.  cg_util is the lowest
  unit that has both the cg_base tables and UpperStr. }

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

FUNCTION CurConstScopeBase: INTEGER32;
{ The first const_tbl index that belongs to the innermost open scope, less
  one: a CONST at a higher index was declared in this scope. }
BEGIN
  IF scope_top = 0 THEN CurConstScopeBase := 0
  ELSE CurConstScopeBase := const_scope_stack[scope_top];
END;

FUNCTION SymScopeDepth(si: INTEGER32): INTEGER32;
{ The scope level symbols[si] was declared at: 0 for the compiland, and the
  deepest d whose scope_stack mark lies below si otherwise. }
VAR
  d: INTEGER32;
  done: BOOLEAN;
BEGIN
  d := scope_top;
  done := FALSE;
  WHILE NOT done DO
    IF d = 0 THEN done := TRUE
    ELSE IF scope_stack[d] < si THEN done := TRUE
    ELSE d := d - 1;
  SymScopeDepth := d;
END;

FUNCTION ConstDeclaredDeeper(uname: Str255; depth: INTEGER32): BOOLEAN;
{ Is a CONST spelled uname (already upper-cased) visible from a scope
  deeper than depth? Only the consts that scope and its descendants
  declared are scanned, so a symbol of the innermost scope costs nothing. }
VAR
  i: INTEGER32;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  IF depth < scope_top THEN
    FOR i := const_scope_stack[depth + 1] + 1 TO nconsts DO
      IF UpperStr(const_tbl[i].name) = uname THEN found := TRUE;
  ConstDeclaredDeeper := found;
END;

FUNCTION ConstScopeDepth(ci: INTEGER32): INTEGER32;
{ The scope level const_tbl[ci] was declared at, as SymScopeDepth. }
VAR
  d: INTEGER32;
  done: BOOLEAN;
BEGIN
  d := scope_top;
  done := FALSE;
  WHILE NOT done DO
    IF d = 0 THEN done := TRUE
    ELSE IF const_scope_stack[d] < ci THEN done := TRUE
    ELSE d := d - 1;
  ConstScopeDepth := d;
END;

FUNCTION NameDeclaredDeeper(uname: Str255; depth: INTEGER32): BOOLEAN;
{ Is a symbol or routine spelled uname (already upper-cased) visible from a
  scope deeper than depth? }
VAR
  i: INTEGER32;
  found: BOOLEAN;
BEGIN
  found := FALSE;
  IF depth < scope_top THEN
  BEGIN
    FOR i := scope_stack[depth + 1] + 1 TO nsymbols DO
      IF UpperStr(symbols[i].name) = uname THEN found := TRUE;
    FOR i := routine_scope_stack[depth + 1] + 1 TO nroutines DO
      IF UpperStr(routines[i].name) = uname THEN found := TRUE;
  END;
  NameDeclaredDeeper := found;
END;

FUNCTION LookupConst(name: Str255): INTEGER32;
{ The CONST (or enumeration member) this name denotes here, or 0. Lookup is
  case-insensitive, like LookupSym and LookupRoutine: `CONST Big = 7' is
  also BIG and big. A variable or routine declared in a deeper scope than
  the innermost such CONST hides it. }
VAR
  i: INTEGER32;
  found: INTEGER32;
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  found := 0;
  FOR i := 1 TO nconsts DO
    IF UpperStr(const_tbl[i].name) = uname THEN found := i;
  IF found <> 0 THEN
    IF NameDeclaredDeeper(uname, ConstScopeDepth(found)) THEN found := 0;
  LookupConst := found;
END;

{ ======================= up-level access (static links) ==================

  A nested routine reaches its enclosing routines' locals, parameters and
  FUNCTION results through static links. Every host routine declared inside
  another routine takes its parent frame's environment as a hidden last LLVM
  parameter (env_depth). An environment is an array of pointers in the
  frame's entry block: one slot for each of its variables (or results) that
  a nested routine names, and one for its own static link when a deeper
  routine walks past it. Slots are allocated while the nested bodies are
  lowered, which happens before the frame's own body, and the array is
  materialized in CloseFrame, when its size is known: until then calls pass
  a placeholder. In the nested routine, an up-level name resolves to a
  pointer loaded once in its entry block, and the symbol's llvm_val is
  swapped for that pointer until the routine's frame closes, so every
  lowering path addresses the captured storage unchanged. }

PROCEDURE OpenFrame(fn: ADRMEM; name: Str255; link: ADRMEM);
{ Called with the builder at the new routine's empty entry block, after its
  scope is pushed and before its parameters are bound. }
BEGIN
  IF frame_top >= MAX_FRAMES THEN
    AbortAtLayoutSite('codegen: routines nested too deeply (more than 32 levels)');
  frame_top := frame_top + 1;
  frame_fn[frame_top] := fn;
  frame_name[frame_top] := name;
  frame_link[frame_top] := link;
  frame_env[frame_top] := NIL;
  frame_anchor[frame_top] := NIL;
  IF scope_top = 0 THEN frame_sym_base[frame_top] := 0
  ELSE frame_sym_base[frame_top] := scope_stack[scope_top];
  frame_nslots[frame_top] := 0;
  frame_func_name[frame_top] := '';
  frame_ret_tk[frame_top] := 0;
  frame_ret_slot[frame_top] := NIL;
  frame_ret_state[frame_top] := NIL;
  { Captured pointers are loaded just before this placeholder, so they
    follow every entry alloca and precede the routine's own code. }
  IF link <> NIL THEN
    frame_anchor[frame_top] := LLVMBuildAlloca(builder, i8ty, MakeCStr('env.anchor'));
END;

PROCEDURE SetFrameResult(func_name: Str255; ret_tk: INTEGER; slot, state: ADRMEM);
BEGIN
  frame_func_name[frame_top] := func_name;
  frame_ret_tk[frame_top] := ret_tk;
  frame_ret_slot[frame_top] := slot;
  frame_ret_state[frame_top] := state;
END;

FUNCTION EnvSlotIndex(d, key: INTEGER32; val: ADRMEM): INTEGER32;
{ The zero-based slot of key in frame d's environment, added on first use
  with the value CloseFrame stores in it. }
VAR
  k, base, found: INTEGER32;
BEGIN
  base := (d - 1) * MAX_ENV_SLOTS;
  found := -1;
  FOR k := 1 TO frame_nslots[d] DO
    IF env_slot_key[base + k] = key THEN found := k - 1;
  IF found < 0 THEN
  BEGIN
    IF frame_nslots[d] >= MAX_ENV_SLOTS THEN
      AbortAtLayoutSite('codegen: too many variables of one routine are used by its nested routines');
    frame_nslots[d] := frame_nslots[d] + 1;
    env_slot_key[base + frame_nslots[d]] := key;
    env_slot_val[base + frame_nslots[d]] := val;
    found := frame_nslots[d] - 1;
  END;
  EnvSlotIndex := found;
END;

FUNCTION EnvSlotAddr(env: ADRMEM; k: INTEGER32): ADRMEM;
VAR
  idx: ADRMEM;
BEGIN
  idx := AllocPtrArray(1);
  SetPtrArrayElem(idx, 0, LLVMConstInt(i64ty, k, 0));
  EnvSlotAddr := LLVMBuildGEP2(builder, i8ptrty, env, idx, 1, MakeCStr('env.slot'));
END;

PROCEDURE RequireFrameLinks(d: INTEGER32; what: Str255);
{ Every frame inside frame d, up to the current one, must have a static
  link: DEVICE routines and [C] routines have none. }
VAR
  e: INTEGER32;
  msg: Str255;
BEGIN
  FOR e := d + 1 TO frame_top DO
    IF frame_link[e] = NIL THEN
    BEGIN
      msg := 'codegen: routine ';
      AppendText(msg, frame_name[frame_top]);
      AppendText(msg, ' cannot use ');
      AppendText(msg, what);
      AppendText(msg, ' of enclosing routine ');
      AppendText(msg, frame_name[d]);
      IF is_device_compiland THEN AppendText(msg, ' in DEVICE code')
      ELSE
      BEGIN
        AppendText(msg, ' through [C] routine ');
        AppendText(msg, frame_name[e]);
      END;
      AbortAtLayoutSite(msg);
    END;
END;

FUNCTION FrameEnvFor(d: INTEGER32; callee: Str255): ADRMEM;
{ Frame d's environment as a value of the current routine, built at the
  builder's position: the static link a routine nested in frame d takes. }
VAR
  v: ADRMEM;
  e, k: INTEGER32;
  what: Str255;
BEGIN
  IF d = frame_top THEN
  BEGIN
    IF frame_env[d] = NIL THEN frame_env[d] := EntryAlloca(i8ptrty, 'env.pending');
    v := frame_env[d];
  END
  ELSE
  BEGIN
    IF callee <> '' THEN
    BEGIN
      what := 'nested routine ';
      AppendText(what, callee);
      RequireFrameLinks(d, what);
    END;
    v := frame_link[frame_top];
    e := frame_top - 1;
    WHILE e > d DO
    BEGIN
      k := EnvSlotIndex(e, ENV_KEY_LINK, frame_link[e]);
      v := LLVMBuildLoad2(builder, i8ptrty, EnvSlotAddr(v, k), MakeCStr('env.link'));
      e := e - 1;
    END;
  END;
  FrameEnvFor := v;
END;

FUNCTION CapturedFramePtr(d, key: INTEGER32; val: ADRMEM; what: Str255): ADRMEM;
{ The pointer, valid anywhere in the current routine, to what slot key of
  enclosing frame d holds (val, a value of frame d's own routine). }
VAR
  i, k: INTEGER32;
  saved_bb, env, res: ADRMEM;
BEGIN
  res := NIL;
  FOR i := 1 TO ncaptures DO
    IF (capture_frame[i] = frame_top) AND (capture_owner[i] = d) AND
       (capture_key[i] = key) THEN res := capture_val[i];
  IF res = NIL THEN
  BEGIN
    RequireFrameLinks(d, what);
    IF ncaptures >= MAX_CAPTURES THEN
      AbortAtLayoutSite('codegen: too many up-level variable uses');
    saved_bb := LLVMGetInsertBlock(builder);
    LLVMPositionBuilderBefore(builder, frame_anchor[frame_top]);
    env := FrameEnvFor(d, '');
    k := EnvSlotIndex(d, key, val);
    res := LLVMBuildLoad2(builder, i8ptrty, EnvSlotAddr(env, k), MakeCStr('env.up'));
    LLVMPositionBuilderAtEnd(builder, saved_bb);
    ncaptures := ncaptures + 1;
    capture_frame[ncaptures] := frame_top;
    capture_owner[ncaptures] := d;
    capture_key[ncaptures] := key;
    capture_val[ncaptures] := res;
    capture_old[ncaptures] := NIL;
  END;
  CapturedFramePtr := res;
END;

PROCEDURE CaptureSym(symi: INTEGER32);
{ Make symbols[symi] usable from the current routine when it belongs to an
  enclosing routine's activation: swap its storage for a captured pointer.
  Compiland-level and STATIC storage (LLVM constants) needs no capture. }
VAR
  d, owner, i: INTEGER32;
  v, orig, p, up: ADRMEM;
  done: BOOLEAN;
  what: Str255;
BEGIN
  done := (frame_top < 2) OR capture_suspended;
  owner := 0;
  v := NIL;
  IF NOT done THEN
  BEGIN
    FOR d := 1 TO frame_top DO
      IF frame_sym_base[d] < symi THEN owner := d;
    IF (owner = 0) OR (owner = frame_top) THEN done := TRUE;
  END;
  IF NOT done THEN
  BEGIN
    v := symbols[symi].llvm_val;
    IF v = NIL THEN done := TRUE
    ELSE IF LLVMIsConstant(v) <> 0 THEN done := TRUE;
  END;
  IF NOT done THEN
    FOR i := 1 TO ncaptures DO
      IF (capture_frame[i] = frame_top) AND (capture_key[i] = symi) THEN done := TRUE;
  IF NOT done THEN
  BEGIN
    { The owner's own storage, even if an intermediate frame swapped it. }
    orig := v;
    FOR i := ncaptures DOWNTO 1 DO
      IF capture_key[i] = symi THEN orig := capture_old[i];
    IF symbols[symi].is_param THEN what := 'parameter ' ELSE what := 'local ';
    AppendText(what, symbols[symi].name);
    p := CapturedFramePtr(owner, symi, orig, what);
    capture_old[ncaptures] := v;
    symbols[symi].llvm_val := p;
    { A conformant STRING/LSTRING formal's UPPER is found through its data
      pointer, so capture the owner's UPPER slot too and register it for
      the captured pointer. }
    up := NIL;
    FOR i := 1 TO nborrowed DO
      IF borrowed_data[i] = orig THEN up := borrowed_upper[i];
    IF up <> NIL THEN
    BEGIN
      up := CapturedFramePtr(owner, ENV_KEY_UPPER_BASE - symi, up, what);
      IF nborrowed >= MAX_BORROWED THEN
        AbortWith('codegen: too many super-array STRING/LSTRING formals');
      nborrowed := nborrowed + 1;
      borrowed_data[nborrowed] := p;
      borrowed_upper[nborrowed] := up;
    END;
  END;
END;

PROCEDURE CloseFrame;
{ Called with the routine's body complete, before its scope is popped. }
VAR
  d, k, base: INTEGER32;
  env, v, next, saved_bb: ADRMEM;
BEGIN
  d := frame_top;
  IF frame_env[d] <> NIL THEN
  BEGIN
    IF frame_nslots[d] = 0 THEN env := LLVMConstNull(i8ptrty)
    ELSE
    BEGIN
      saved_bb := LLVMGetInsertBlock(builder);
      env := EntryAlloca(LLVMArrayType(i8ptrty, frame_nslots[d]), 'env');
      base := (d - 1) * MAX_ENV_SLOTS;
      FOR k := 1 TO frame_nslots[d] DO
      BEGIN
        { Fill each slot right after its value is defined (an entry
          alloca), or right after the array for an incoming parameter. }
        v := env_slot_val[base + k];
        IF LLVMIsAInstruction(v) <> NIL THEN next := LLVMGetNextInstruction(v)
        ELSE next := LLVMGetNextInstruction(env);
        LLVMPositionBuilderBefore(builder, next);
        LLVMBuildStore(builder, v, EnvSlotAddr(env, k - 1));
      END;
      LLVMPositionBuilderAtEnd(builder, saved_bb);
    END;
    LLVMReplaceAllUsesWith(frame_env[d], env);
    LLVMInstructionEraseFromParent(frame_env[d]);
  END;
  IF frame_anchor[d] <> NIL THEN LLVMInstructionEraseFromParent(frame_anchor[d]);
  WHILE (ncaptures > 0) AND THEN (capture_frame[ncaptures] = d) DO
  BEGIN
    IF capture_key[ncaptures] > 0 THEN
      symbols[capture_key[ncaptures]].llvm_val := capture_old[ncaptures];
    ncaptures := ncaptures - 1;
  END;
  frame_top := frame_top - 1;
END;

FUNCTION LookupSym(name: Str255): INTEGER32;
{ The variable (or parameter, or WITH field) this name denotes here, or 0.
  A CONST declared in a deeper scope than the innermost such symbol hides
  it, so the name denotes that CONST instead and every caller falls through
  to LookupConst -- CodegenExpr, CASE labels, FOR bounds and the constant
  folder's shadowing guard alike. }
VAR
  i: INTEGER32;
  found: INTEGER32;
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  found := 0;
  FOR i := 1 TO nsymbols DO
    IF UpperStr(symbols[i].name) = uname THEN found := i;
  IF found <> 0 THEN
    IF ConstDeclaredDeeper(uname, SymScopeDepth(found)) THEN found := 0;
  { An enclosing routine's variable is reached through the static link. }
  IF found <> 0 THEN CaptureSym(found);
  LookupSym := found;
END;

FUNCTION EnclosingResultFrame(name: Str255): INTEGER32;
{ The frame of the enclosing FUNCTION whose result `name := ...` assigns
  from a nested routine, or 0. The current FUNCTION is not included (its
  own result is cur_func_ret_slot), and a variable declared inside that
  FUNCTION, or deeper, hides its name. }
VAR
  d, found, symi: INTEGER32;
  uname: Str255;
BEGIN
  uname := UpperStr(name);
  found := 0;
  FOR d := 1 TO frame_top - 1 DO
    IF frame_func_name[d] <> '' THEN
      IF UpperStr(frame_func_name[d]) = uname THEN found := d;
  IF found <> 0 THEN
  BEGIN
    symi := LookupSym(name);
    IF symi > frame_sym_base[found] THEN found := 0;
  END;
  EnclosingResultFrame := found;
END;

FUNCTION UserRoutineShadows(name: Str255): BOOLEAN;
{ "Is a user routine of this name visible here" -- the codegen counterpart of
  tc_base.pas's UserDeclarationShadows, and it has to answer the same way, or
  a call the typechecker bound to a builtin is lowered as a user call (or the
  reverse). LookupRoutine only searches live scopes because PopScope trims
  the table, so a nested routine cannot answer for an outer-level call. }
BEGIN
  UserRoutineShadows := LookupRoutine(name) <> 0;
END;

FUNCTION IsPredeclaredMaximum(uname: Str255): BOOLEAN;
{ Is uname (already upper-cased) MAXINT, MAXWORD or a 32- or 64-bit form? }
BEGIN
  IsPredeclaredMaximum := (uname = 'MAXINT') OR (uname = 'MAXWORD') OR
    (uname = 'MAXINT32') OR (uname = 'MAXWORD32') OR (uname = 'MAXINT64') OR
    (uname = 'MAXWORD64');
END;

FUNCTION UserDeclarationHides(name: Str255): BOOLEAN;
{ Is a user variable, parameter, WITH field, CONST (enumeration members
  included) or routine of this spelling visible here? Such a declaration
  hides a predeclared identifier of the same name (IBM Pascal, Aug. 1981,
  p.3-7), as a visible symbol does in tc_base.pas's scoped table. }
BEGIN
  UserDeclarationHides := (LookupSym(name) <> 0) OR
    (LookupConst(name) <> 0) OR (LookupRoutine(name) <> 0);
END;

FUNCTION PredeclaredConstVisible(name: Str255): BOOLEAN;
{ Is name a predeclared integer maximum (IsPredeclaredMaximum) not hidden
  here by a user variable, parameter, WITH field, CONST or routine of that
  spelling? Like any predeclared identifier the maxima yield to a user
  declaration (IBM Pascal, Aug. 1981, p.3-7), as tc_base.pas's scoped
  symbols do. }
BEGIN
  PredeclaredConstVisible := IsPredeclaredMaximum(UpperStr(name)) AND
    NOT UserDeclarationHides(name);
END;

FUNCTION IsDeviceIndexName(uname: Str255): BOOLEAN;
{ Is uname (already upper-cased) one of the DEVICE index builtins
  THREADIDX_X .. GRIDDIM_Z? tc_expr.pas's IsDeviceIndexName lists the
  same twelve names. }
BEGIN
  IsDeviceIndexName :=
    (uname = 'THREADIDX_X') OR (uname = 'THREADIDX_Y') OR
    (uname = 'THREADIDX_Z') OR (uname = 'BLOCKIDX_X') OR
    (uname = 'BLOCKIDX_Y') OR (uname = 'BLOCKIDX_Z') OR
    (uname = 'BLOCKDIM_X') OR (uname = 'BLOCKDIM_Y') OR
    (uname = 'BLOCKDIM_Z') OR (uname = 'GRIDDIM_X') OR
    (uname = 'GRIDDIM_Y') OR (uname = 'GRIDDIM_Z');
END;

FUNCTION DeviceIndexVisible(name: Str255): BOOLEAN;
{ Is name a DEVICE index builtin not hidden by a user declaration
  (UserDeclarationHides)? Like the predeclared maxima, THREADIDX_X and
  its siblings yield to a user VAR, CONST or routine of that spelling
  (NEW-8). }
BEGIN
  DeviceIndexVisible := IsDeviceIndexName(UpperStr(name)) AND
    NOT UserDeclarationHides(name);
END;

FUNCTION AllocPtrArray(n: INTEGER32): ADRMEM;
{ The N-element generalization of the malloc-and-cast idiom jsonutil.pas
  already uses for C strings: llvm-c takes LLVMTypeRef*/LLVMValueRef*
  arrays as a raw pointer + count. }
BEGIN
  AllocPtrArray := malloc(n * 8);
END;

PROCEDURE SetPtrArrayElem(arr: ADRMEM; idx: INTEGER32; v: ADRMEM);
VAR
  base, cell: PAdr;
BEGIN
  base := arr;
  cell := base + idx;
  cell^ := v;
END;

FUNCTION InitckPendingAt(i: INTEGER32): PInitckPending;
{ Entry i (1-based) of the deferred-effect queue. }
BEGIN
  InitckPendingAt := initck_pending + ((i - 1) * SIZEOF(InitckPending));
END;

PROCEDURE InitckQueueRelease(p: ADRMEM; tid: INTEGER);
{ Defer an effect to the enclosing call (InitckReleaseAtCall). The queue
  grows instead of applying an effect early: an early release would let a
  later actual read the storage as initialized. }
VAR
  e: PInitckPending;
BEGIN
  IF initck_npending = initck_pending_cap THEN
  BEGIN
    IF initck_pending_cap = 0 THEN initck_pending_cap := 64
    ELSE initck_pending_cap := initck_pending_cap * 2;
    initck_pending := realloc(initck_pending, initck_pending_cap * SIZEOF(InitckPending));
    IF initck_pending = NIL THEN AbortWith('codegen: out of memory for INITCK call effects');
  END;
  initck_npending := initck_npending + 1;
  e := InitckPendingAt(initck_npending);
  e^.p := p;
  e^.guard := NIL;
  e^.tid := tid;
END;

PROCEDURE EmitBlockCopy(dst: ADRMEM; src: ADRMEM; nbytes: INTEGER32);
{ memmove(dst, src, nbytes) via the target program's own memmove extern --
  the same block-copy shape formerly inlined at the needs_copy prologue
  site (before that path moved to a first-class LLVM aggregate value) and
  now shared by the [C] FOREIGN byval caller-side temp-copy path in
  CodegenCallCommon. Bitcasts both pointers to i8* first since memmove's
  declared signature is untyped. }
VAR
  copy_dst, copy_src, copy_result: ADRMEM;
  copy_call_args: ADRMEM;
BEGIN
  copy_dst := LLVMBuildBitCast(builder, dst, i8ptrty, MakeCStr(''));
  copy_src := LLVMBuildBitCast(builder, src, i8ptrty, MakeCStr(''));
  copy_call_args := AllocPtrArray(3);
  SetPtrArrayElem(copy_call_args, 0, copy_dst);
  SetPtrArrayElem(copy_call_args, 1, copy_src);
  SetPtrArrayElem(copy_call_args, 2, LLVMConstInt(i64ty, nbytes, 0));
  copy_result := LLVMBuildCall2(builder, memmove_fnty, memmove_fn, copy_call_args, 3, MakeCStr(''));
END;

FUNCTION LargeAggregateTy(ty: ADRMEM): BOOLEAN;
{ An LLVM array or struct type of at least LARGE_AGGREGATE_BYTES. A
  first-class value of such a type is split by SelectionDAG into one node
  per scalar leaf; past 65,535 leaves one node gets more operands than it
  can hold and clang crashes at O0, and long before that the split is slow
  at every level. }
VAR
  kind: CINT;
BEGIN
  kind := LLVMGetTypeKind(ty);
  IF (kind = 10) OR (kind = 11) THEN { LLVMStructTypeKind, LLVMArrayTypeKind }
    LargeAggregateTy := LLVMABISizeOfType(LLVMGetModuleDataLayout(modl), ty) >=
                        LARGE_AGGREGATE_BYTES
  ELSE
    LargeAggregateTy := FALSE;
END;

FUNCTION AggregateSizeConst(ty: ADRMEM): ADRMEM;
BEGIN
  AggregateSizeConst := LLVMConstInt(i64ty,
    LLVMABISizeOfType(LLVMGetModuleDataLayout(modl), ty), 0);
END;

PROCEDURE LowerLargeConstantStore(store: ADRMEM);
{ store <large constant>, p  ==>  memset(p, 0) for a zero constant, else a
  memcpy from a private constant global holding the value. }
VAR
  v, ty, gv, discard: ADRMEM;
BEGIN
  v := LLVMGetOperand(store, 0);
  ty := LLVMTypeOf(v);
  LLVMPositionBuilderBefore(builder, store);
  IF LLVMIsNull(v) <> 0 THEN
    discard := LLVMBuildMemSet(builder, LLVMGetOperand(store, 1),
                               LLVMConstInt(i8ty, 0, 0), AggregateSizeConst(ty),
                               LLVMGetAlignment(store))
  ELSE
  BEGIN
    gv := LLVMAddGlobal(modl, ty, MakeCStr('aggconst'));
    LLVMSetInitializer(gv, v);
    LLVMSetGlobalConstant(gv, 1);
    LLVMSetLinkage(gv, 9); { LLVMPrivateLinkage }
    discard := LLVMBuildMemCpy(builder, LLVMGetOperand(store, 1),
                               LLVMGetAlignment(store), gv,
                               LLVMGetAlignment(gv), AggregateSizeConst(ty));
  END;
  LLVMInstructionEraseFromParent(store);
END;

FUNCTION LowerLargeAggregateLoad(fn, load, next: ADRMEM): ADRMEM;
{ A large first-class load whose every use stores it whole. A load and
  the store right after it become one memmove (source and destination may
  be the same variable). Otherwise the load snapshots its source into an
  entry-block temporary with memcpy, at the load's own position, and each
  store copies from that temporary, so writes between the load and a
  store cannot change the value stored. Returns the instruction the walk
  continues with. Loads with any other use are left alone. }
VAR
  u, user, ty, src, temp, discard, saved_fn: ADRMEM;
  only_stores: BOOLEAN;
  nuses: INTEGER32;
BEGIN
  only_stores := TRUE;
  nuses := 0;
  u := LLVMGetFirstUse(load);
  WHILE u <> NIL DO
  BEGIN
    user := LLVMGetUser(u);
    IF LLVMIsAStoreInst(user) = NIL THEN only_stores := FALSE
    ELSE IF LLVMGetOperand(user, 0) <> load THEN only_stores := FALSE;
    nuses := nuses + 1;
    u := LLVMGetNextUse(u);
  END;
  LowerLargeAggregateLoad := next;
  IF only_stores THEN
  BEGIN
    ty := LLVMTypeOf(load);
    src := LLVMGetOperand(load, 0);
    IF (nuses = 1) AND (LLVMGetUser(LLVMGetFirstUse(load)) = next) THEN
    BEGIN
      LLVMPositionBuilderBefore(builder, next);
      discard := LLVMBuildMemMove(builder, LLVMGetOperand(next, 1),
                                  LLVMGetAlignment(next), src,
                                  LLVMGetAlignment(load), AggregateSizeConst(ty));
      LowerLargeAggregateLoad := LLVMGetNextInstruction(next);
      LLVMInstructionEraseFromParent(next);
    END
    ELSE
    BEGIN
      IF nuses > 0 THEN
      BEGIN
        saved_fn := cur_fn;
        cur_fn := fn;
        temp := EntryAlloca(ty, 'aggcopy');
        cur_fn := saved_fn;
        LLVMPositionBuilderBefore(builder, load);
        discard := LLVMBuildMemCpy(builder, temp, LLVMGetAlignment(temp), src,
                                   LLVMGetAlignment(load), AggregateSizeConst(ty));
        WHILE LLVMGetFirstUse(load) <> NIL DO
        BEGIN
          user := LLVMGetUser(LLVMGetFirstUse(load));
          LLVMPositionBuilderBefore(builder, user);
          discard := LLVMBuildMemCpy(builder, LLVMGetOperand(user, 1),
                                     LLVMGetAlignment(user), temp,
                                     LLVMGetAlignment(temp), AggregateSizeConst(ty));
          LLVMInstructionEraseFromParent(user);
        END;
      END;
      LowerLargeAggregateLoad := LLVMGetNextInstruction(load);
    END;
    LLVMInstructionEraseFromParent(load);
  END;
END;

PROCEDURE LowerLargeAggregateCopies;
{ Codegen moves aggregates as first-class LLVM values: an assignment is a
  load of the whole source and a store of it, a function result is loaded
  out of its sret slot, a result slot is zeroed by a store of
  zeroinitializer. For a large aggregate (LargeAggregateTy) that shape
  crashes clang at O0 and is slow at every level, so this pass, run on the
  finished module, rewrites a large constant store as memset/memcpy and a
  large load whose only uses are whole stores as memmove/memcpy. A large
  value used any other way (an NVPTX by-value parameter, for one) keeps
  its first-class form; host results never travel as one, they go
  through the hidden sret pointer. }
VAR
  fn, bb, inst, next: ADRMEM;
BEGIN
  fn := LLVMGetFirstFunction(modl);
  WHILE fn <> NIL DO
  BEGIN
    bb := LLVMGetFirstBasicBlock(fn);
    WHILE bb <> NIL DO
    BEGIN
      inst := LLVMGetFirstInstruction(bb);
      WHILE inst <> NIL DO
      BEGIN
        next := LLVMGetNextInstruction(inst);
        IF LLVMIsAStoreInst(inst) <> NIL THEN
        BEGIN
          IF LargeAggregateTy(LLVMTypeOf(LLVMGetOperand(inst, 0))) THEN
            IF LLVMIsConstant(LLVMGetOperand(inst, 0)) <> 0 THEN
              LowerLargeConstantStore(inst);
        END
        ELSE IF LLVMIsALoadInst(inst) <> NIL THEN
          IF LargeAggregateTy(LLVMTypeOf(inst)) THEN
            next := LowerLargeAggregateLoad(fn, inst, next);
        inst := next;
      END;
      bb := LLVMGetNextBasicBlock(bb);
    END;
    fn := LLVMGetNextFunction(fn);
  END;
END;

PROCEDURE AppendText(VAR s: Str255; t: Str255);
{ Append, silently stopping at the 255-character capacity. }
VAR
  i: INTEGER;
BEGIN
  FOR i := 1 TO ORD(t[0]) DO AppendChar(s, t[i]);
END;

FUNCTION CgElide(s: Str255; maxlen: INTEGER): Str255;
{ s cut to at most maxlen characters by replacing its middle with `...', so
  a diagnostic keeps both the start of a long name and the end that tells
  it apart from a similar one. }
VAR
  r: Str255;
  head, tail, i, len: INTEGER;
BEGIN
  len := ORD(s[0]);
  IF len <= maxlen THEN
    r := s
  ELSE IF maxlen < 5 THEN
  BEGIN
    r := s;
    IF maxlen < 0 THEN r[0] := CHR(0) ELSE r[0] := CHR(maxlen);
  END
  ELSE
  BEGIN
    head := (maxlen - 3) DIV 2;
    tail := maxlen - 3 - head;
    r := '';
    FOR i := 1 TO head DO AppendChar(r, s[i]);
    AppendText(r, '...');
    FOR i := len - tail + 1 TO len DO AppendChar(r, s[i]);
  END;
  CgElide := r;
END;

PROCEDURE SymbolHashFeed(VAR h: INTEGER64; t: Str255);
{ A polynomial hash modulo the prime 4294967291 over t and a terminator, so
  (a, b) and (a', b') with the same concatenation still differ. }
VAR
  k: INTEGER;
BEGIN
  FOR k := 1 TO ORD(t[0]) DO
    h := (h * 31 + ORD(t[k])) MOD 4294967291;
  h := (h * 31 + 1) MOD 4294967291;
END;

FUNCTION BoundedSymbol(a, b: Str255): Str255;
{ The LLVM symbol a+b, where b is usually an identifier of up to 255
  characters. When the whole does not fit a Str255, its first 246
  characters are kept and `.' plus eight hex digits of a hash of all of
  a and b are appended, so two long names that share a prefix still
  get different symbols (and every compiland spells the same name the
  same way, as pascal_init_<unit> needs). }
VAR
  r: Str255;
  h: INTEGER64;
  i, d: INTEGER;
  hex: Str255;
BEGIN
  IF ORD(a[0]) + ORD(b[0]) <= 255 THEN
  BEGIN
    r := a;
    AppendText(r, b);
  END
  ELSE
  BEGIN
    h := 0;
    SymbolHashFeed(h, a);
    SymbolHashFeed(h, b);
    r := a;
    AppendText(r, b);
    r[0] := CHR(246);
    hex := '01234567';
    FOR i := 8 DOWNTO 1 DO
    BEGIN
      d := RETYPE(INTEGER, h MOD 16);
      IF d < 10 THEN hex[i] := CHR(ORD('0') + d)
      ELSE hex[i] := CHR(ORD('a') + d - 10);
      h := h DIV 16;
    END;
    AppendChar(r, '.');
    AppendText(r, hex);
  END;
  BoundedSymbol := r;
END;

PROCEDURE AppendLocation(VAR msg: Str255; location: ADRMEM);
{ The located-diagnostic suffix every stage uses: ` at line L column C',
  plus ` of file NAME' when the location carries the `file' of an included
  source. Nothing for a missing location or a legacy 0:0 one. When msg and
  the suffix do not both fit a Str255, the middle of msg (usually a long
  identifier) is elided rather than the location. }
VAR
  line, column: INTEGER32;
  suffix: Str255;
  room: INTEGER;
BEGIN
  IF location = NIL THEN RETURN;
  line := GetInt(location, 'line');
  column := GetInt(location, 'column');
  IF (line > 0) AND (column > 0) THEN
  BEGIN
    suffix := ' at line ';
    AppendText(suffix, IntToStr255(line));
    AppendText(suffix, ' column ');
    AppendText(suffix, IntToStr255(column));
    IF HasKey(location, 'file') THEN
    BEGIN
      AppendText(suffix, ' of file ');
      { The file name keeps whatever msg leaves, and at least 150. }
      room := 255 - ORD(msg[0]) - ORD(suffix[0]);
      IF room < 150 THEN room := 150;
      AppendText(suffix, CgElide(GetStr(location, 'file'), room));
    END;
    msg := CgElide(msg, 255 - ORD(suffix[0]));
    AppendText(msg, suffix);
  END;
END;

PROCEDURE EmitDiagFile(location: ADRMEM);
{ Before a located runtime failure call: when the location is in an
  included file, store its name in the runtime's thread-local
  pas_diag_file (runtime/diagnostics.c), which the failure message then
  names. A primary-file location emits nothing, so its IR is unchanged.
  The builder must be in the failure block: the store is the failure
  path's alone. }
VAR
  g: ADRMEM;
BEGIN
  IF location = NIL THEN RETURN;
  IF NOT HasKey(location, 'file') THEN RETURN;
  g := LLVMGetNamedGlobal(modl, MakeCStr('pas_diag_file'));
  IF g = NIL THEN
  BEGIN
    g := LLVMAddGlobal(modl, i8ptrty, MakeCStr('pas_diag_file'));
    LLVMSetThreadLocal(g, 1);
  END;
  LLVMBuildStore(builder, LLVMBuildGlobalStringPtr(builder,
    MakeCStr(GetStr(location, 'file')), MakeCStr('diag.file')), g);
END;

FUNCTION NodeDiagLocation(node: ADRMEM): ADRMEM;
{ The location a run-time check reports for a node: its statement or
  designator `location', else the `read_location' of a read, else the
  `op_location' of an operation. NIL for a node without any (a legacy
  AST, or none at all). }
VAR
  location: ADRMEM;
BEGIN
  location := NIL;
  IF node <> NIL THEN
  BEGIN
    location := GetObjOrNil(node, 'location');
    IF location = NIL THEN location := GetObjOrNil(node, 'read_location');
    IF location = NIL THEN location := GetObjOrNil(node, 'op_location');
  END;
  NodeDiagLocation := location;
END;

BEGIN
END.
