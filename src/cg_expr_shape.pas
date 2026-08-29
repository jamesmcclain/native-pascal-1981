{ Implementations for cg_expr_shape. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'cg_base.inc'*)
(*$INCLUDE:'cg_util.inc'*)
(*$INCLUDE:'cg_types.inc'*)
(*$INCLUDE:'cg_symbols.inc'*)
(*$INCLUDE:'cg_expr_shape.inc'*)
IMPLEMENTATION OF cg_expr_shape;

FUNCTION StaticDesignatorType(node: ADRMEM): INTEGER;
{ Type-only counterpart of ComputeDesignatorAddress: walks the same
  INDEX/DEREF/FIELD selector chain and mirrors its type transitions
  exactly (including INDEX-on-LSTRING/STRING correctly yielding CHAR, via
  the same types[].elem_tid = TK_CHAR those two register with), but emits
  no IR. Safe to call from a pure predicate like IsStringShapedExpr, which
  must not have codegen side effects merely from being asked "is this
  expression string-shaped" -- unlike ComputeDesignatorAddress, which
  always builds real GEP/load instructions. Returns TK_UNKNOWN for any
  selector shape it can't resolve (undefined variable/field, a selector
  applied to the wrong kind of value), matching the AbortWith-worthy cases
  ComputeDesignatorAddress would reject outright -- callers here only ever
  ask "is this shaped like X", so returning TK_UNKNOWN and letting the
  caller answer FALSE is the right response, not an abort. }
VAR
  nm, fname: Str255;
  symi: INTEGER32;
  cur_tid: INTEGER;
  selectors, sel: ADRMEM;
  nsel, si: INTEGER32;
  kind: Str255;
  fi: INTEGER;
  failed: BOOLEAN;
BEGIN
  nm := GetStr(node, 'name');
  symi := LookupSym(nm);
  IF symi = 0 THEN
  BEGIN
    StaticDesignatorType := TK_UNKNOWN;
    RETURN;
  END;
  cur_tid := symbols[symi].tk;
  selectors := GetObj(node, 'selectors');
  nsel := ArrSize(selectors);
  failed := FALSE;
  si := 0;
  WHILE (si < nsel) AND (NOT failed) DO
  BEGIN
    sel := ArrItem(selectors, si);
    kind := GetStr(sel, 'kind');
    IF kind = 'INDEX' THEN
    BEGIN
      IF (TypeKind(cur_tid) <> TK_ARRAY) AND (TypeKind(cur_tid) <> TK_LSTRING) AND (TypeKind(cur_tid) <> TK_STRING) THEN
        failed := TRUE
      ELSE
        cur_tid := types[cur_tid].elem_tid;
    END
    ELSE IF kind = 'DEREF' THEN
    BEGIN
      IF (TypeKind(cur_tid) = TK_FILE) OR (TypeKind(cur_tid) = TK_POINTER) THEN
        cur_tid := types[cur_tid].elem_tid
      ELSE
        failed := TRUE;
    END
    ELSE IF kind = 'FIELD' THEN
    BEGIN
      IF TypeKind(cur_tid) = TK_LSTRING THEN
      BEGIN
        { .LEN, the length byte: a CHAR, so the designator is not
          string-shaped. Any other field name is an error the real
          designator path reports. }
        IF UpperStr(GetStr(sel, 'index_or_field')) = 'LEN' THEN
          cur_tid := types[cur_tid].elem_tid
        ELSE
          failed := TRUE;
      END
      ELSE IF TypeKind(cur_tid) <> TK_RECORD THEN
        failed := TRUE
      ELSE BEGIN
        fname := GetStr(sel, 'index_or_field');
        fi := LookupField(cur_tid, fname);
        IF fi = 0 THEN failed := TRUE
        ELSE cur_tid := fields[fi].field_tid;
      END;
    END
    ELSE
      failed := TRUE;
    si := si + 1;
  END;
  IF failed THEN StaticDesignatorType := TK_UNKNOWN
  ELSE StaticDesignatorType := cur_tid;
END;

FUNCTION IsStringShapedExpr(node: ADRMEM): BOOLEAN;
{ Identifies literal and variable/designator expressions whose resolved type
  is LSTRING or STRING.  This stays type-only: calling it emits no IR. }
VAR
  symi: INTEGER32;
  dtid: INTEGER;
BEGIN
  IF NodeType(node) = 'StringLiteral' THEN
    IsStringShapedExpr := TRUE
  ELSE IF NodeType(node) = 'Identifier' THEN
  BEGIN
    symi := LookupSym(GetStr(node, 'name'));
    { Plain AND is not short-circuit in this dialect.  Guard the 1-based
      symbol table before inspecting its type. }
    IF symi = 0 THEN
      IsStringShapedExpr := FALSE
    ELSE
      IsStringShapedExpr := (TypeKind(symbols[symi].tk) = TK_LSTRING) OR
        (TypeKind(symbols[symi].tk) = TK_STRING);
  END
  ELSE IF NodeType(node) = 'Designator' THEN
  BEGIN
    dtid := StaticDesignatorType(node);
    IsStringShapedExpr := (TypeKind(dtid) = TK_LSTRING) OR
      (TypeKind(dtid) = TK_STRING);
  END
  ELSE
    IsStringShapedExpr := FALSE;
END;

BEGIN
END.
