{ Implementations for cg_util. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
IMPLEMENTATION OF cg_util;

VAR
  expr_depth, stmt_depth: INTEGER;

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

PROCEDURE AbortWith2(prefix: Str255; suffix: Str255);
VAR
  msg: Str255;
BEGIN
  msg := prefix;
  CONCAT(msg, suffix);
  AbortWith(msg);
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

BEGIN
END.
