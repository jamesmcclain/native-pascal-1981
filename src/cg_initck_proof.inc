{ Conservative forward definite-initialization analysis. Compiler-owned node
  identities, never trusted input-AST annotations. Only guards are eliminated;
  all stores, shadow state and unchecked transport remain intact. }

FUNCTION InitckProofBlocked(node: ADRMEM): BOOLEAN;
VAR i: INTEGER32; found: BOOLEAN; nt: Str255;
BEGIN
  nt := NodeType(node);
  found := (nt = 'GotoStmt') OR (nt = 'LabelStmt');
  FOR i := 0 TO ArrSize(node) - 1 DO
    IF InitckProofBlocked(ArrItem(node, i)) THEN found := TRUE;
  InitckProofBlocked := found;
END;

FUNCTION InitckProofExpr(node: ADRMEM; symi: INTEGER32;
                         ready, record_reads: BOOLEAN): BOOLEAN;
{ Side-effect-free scalar syntax only. Calls, selected storage, result slots
  and unfamiliar forms cannot supply a proof. Checked scalar reads establish
  defined values on the continuing path; unchecked reads need an incoming fact. }
VAR nt: Str255; si: INTEGER32; ok, left_ok, right_ok: BOOLEAN;
BEGIN
  nt := NodeType(node);
  ok := (nt = 'IntLiteral') OR (nt = 'BoolLiteral') OR (nt = 'CharLiteral');
  IF (nt = 'Identifier') OR (nt = 'Designator') THEN
  BEGIN
    si := LookupSym(GetStr(node, 'name'));
    IF (si > initck_scope_base) AND (ArrSize(GetObj(node, 'selectors')) = 0) THEN
      IF (symbols[si].init_state <> NIL) AND
         ((symbols[si].tk = TK_INTEGER) OR (symbols[si].tk = TK_BOOLEAN) OR
          (symbols[si].tk = TK_CHAR)) THEN
      BEGIN
        ok := InitckEnabled(node) OR ((si = symi) AND ready);
        IF record_reads AND ready AND (si = symi) AND InitckEnabled(node) THEN
          IF initck_nproven < 4096 THEN
          BEGIN
            initck_nproven := initck_nproven + 1;
            initck_proven_nodes[initck_nproven] := node;
            initck_proven_syms[initck_nproven] := symi;
          END;
      END;
  END
  ELSE IF nt = 'UnaryOp' THEN
    ok := InitckProofExpr(GetObj(node, 'operand'), symi, ready, record_reads)
  ELSE IF nt = 'BinOp' THEN
  BEGIN
    left_ok := InitckProofExpr(GetObj(node, 'left'), symi, ready, record_reads);
    right_ok := InitckProofExpr(GetObj(node, 'right'), symi, ready, record_reads);
    ok := left_ok AND right_ok;
  END;
  InitckProofExpr := ok;
END;

PROCEDURE InitckProofStmt(node: ADRMEM; symi: INTEGER32; VAR ready: BOOLEAN);
{ Must-analysis over assignment sequences and IF intersections. Other
  statements are barriers; loops are not traversed. Unstructured edges
  disable this optimization for the entire routine. }
VAR nt, target_name, sym_name: Str255; target, expr: ADRMEM; i: INTEGER32;
    value_ready, yes_ready, no_ready: BOOLEAN;
BEGIN
  nt := NodeType(node);
  IF (nt = 'Block') OR (nt = 'CompoundStmt') THEN
  BEGIN
    IF nt = 'Block' THEN expr := GetObj(node, 'body')
    ELSE expr := GetObj(node, 'stmts');
    FOR i := 0 TO ArrSize(expr) - 1 DO
      InitckProofStmt(ArrItem(expr, i), symi, ready);
  END
  ELSE IF nt = 'AssignStmt' THEN
  BEGIN
    target := GetObj(node, 'target');
    IF ArrSize(GetObj(target, 'selectors')) <> 0 THEN
    BEGIN
      ready := FALSE;
      RETURN;
    END;
    expr := GetObj(node, 'expr');
    value_ready := InitckProofExpr(expr, symi, ready, FALSE);
    { No read annotations in an expression containing an unknown effect. }
    IF value_ready THEN value_ready := InitckProofExpr(expr, symi, ready, TRUE)
    ELSE ready := FALSE;
    target_name := UpperStr(GetStr(target, 'name'));
    sym_name := UpperStr(symbols[symi].name);
    IF target_name = sym_name THEN ready := value_ready;
  END
  ELSE IF nt = 'IfStmt' THEN
  BEGIN
    expr := GetObj(node, 'cond');
    IF InitckProofExpr(expr, symi, ready, FALSE) THEN
      value_ready := InitckProofExpr(expr, symi, ready, TRUE)
    ELSE ready := FALSE;
    yes_ready := ready;
    no_ready := ready;
    InitckProofStmt(GetObj(node, 'then_branch'), symi, yes_ready);
    IF GetObjOrNil(node, 'else_branch') <> NIL THEN
      InitckProofStmt(GetObj(node, 'else_branch'), symi, no_ready);
    ready := yes_ready AND no_ready;
  END
  ELSE IF nt <> 'EmptyStmt' THEN ready := FALSE;
END;
