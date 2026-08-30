{ Type-expression resolution implementation. }

(*$INCLUDE:'features.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_types.inc'*)
IMPLEMENTATION OF tc_types;

FUNCTION cJSON_GetArraySize(arr: ADRMEM): CINT [C]; EXTERN;
FUNCTION cJSON_GetArrayItem(arr: ADRMEM; index: CINT): ADRMEM [C]; EXTERN;
FUNCTION cJSON_GetStringValue(item: ADRMEM): ADRMEM [C]; EXTERN;

{ ========================== type-expr resolution ======================= }

PROCEDURE ResolveTypeExpr(node: ADRMEM; VAR tk, aux, aux2, idx_tk: INTEGER);
VAR
  nt, name, uname: Str255;
  base_node, elem_node, index_node, bound_node, fields_arr, tup, items, names_arr, ftype_node: ADRMEM;
  variants_arr, arm_node, tag_type_node: ADRMEM;
  inner_tk, inner_aux, inner_aux2, inner_idx: INTEGER;
  ti: INTEGER32;
  rid: INTEGER;
  n, fi, nn, ni, bound_si: INTEGER32;
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
    uname := UpperStr(name);
    { A user TYPE of this name wins over the predeclared meaning. IBM Pascal,
      Aug 1981, p.3-7: predeclared identifiers "can be re-defined by the
      programmer, but doing this is not recommended" -- and none of them is a
      reserved word, the contrast the manual draws for NIL. The compiler's own
      internal uses of the built-in meaning are unaffected (p.6228, on
      BOOLEAN: "the old type is implicitly used by the compiler for things
      like the IF statement"). Matches the reference's resolve_type.

      STRING(n) and LSTRING(n) arrive as NamedTypes carrying a param and are
      built-in string constructors, never the shadowing user type, so they
      skip this probe. }
    ti := 0;
    IF GetObjOrNil(node, 'param') = NIL THEN ti := LookupType(name);
    IF ti <> 0 THEN
    BEGIN
      tk := types[ti].tk;
      aux := types[ti].aux;
      aux2 := types[ti].aux2;
      idx_tk := types[ti].idx_tk;
    END
    ELSE IF uname = 'INTEGER' THEN tk := TK_INTEGER
    ELSE IF uname = 'WORD' THEN tk := TK_WORD
    ELSE IF uname = 'REAL' THEN tk := TK_REAL
    ELSE IF uname = 'BOOLEAN' THEN tk := TK_BOOLEAN
    ELSE IF uname = 'CHAR' THEN tk := TK_CHAR
    ELSE IF uname = 'STRING' THEN tk := TK_STRING
    { LSTRING shares TK_STRING with the fixed STRING -- this v1 type-kind
      model does not track a string's capacity or flavor -- but the two are
      not interchangeable for one construct: .LEN designates an LSTRING's
      leading length byte and is an error on a STRING. aux2 = 1 is the flag
      that tells them apart; nothing else reads aux2 for a string. }
    ELSE IF uname = 'LSTRING' THEN
    BEGIN
      tk := TK_STRING;
      aux2 := 1;
    END
    { Wide integer names retain exact width and signedness. INTEGER16 and
      WORD16 are extension spellings for the vintage 16-bit kinds. }
    ELSE IF (uname = 'INTEGER8') OR (uname = 'INTEGER16') OR (uname = 'INTEGER32') OR (uname = 'INTEGER64') THEN
    BEGIN
      IF active_features.wide_integers OR is_device_compiland THEN
      BEGIN
        IF uname = 'INTEGER8' THEN tk := TK_INTEGER8
        ELSE IF uname = 'INTEGER32' THEN tk := TK_INTEGER32
        ELSE IF uname = 'INTEGER64' THEN tk := TK_INTEGER64
        ELSE tk := TK_INTEGER;
      END
      ELSE BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END;
    END
    ELSE IF (uname = 'WORD8') OR (uname = 'WORD16') OR (uname = 'WORD32') OR (uname = 'WORD64') THEN
    BEGIN
      IF active_features.wide_integers OR is_device_compiland THEN
      BEGIN
        IF uname = 'WORD8' THEN tk := TK_WORD8
        ELSE IF uname = 'WORD32' THEN tk := TK_WORD32
        ELSE IF uname = 'WORD64' THEN tk := TK_WORD64
        ELSE tk := TK_WORD;
      END
      ELSE BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END;
    END
    ELSE IF (uname = 'REAL32') OR (uname = 'REAL64') THEN
    BEGIN
      IF active_features.wide_reals OR is_device_compiland THEN
        tk := TK_REAL
      ELSE BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END;
    END
    { ADRMEM/ADSMEM are vintage address types. The CPTR spelling is part of
      the extended C-ABI aliases. All three use the same coarse pointer tag. }
    ELSE IF (uname = 'ADRMEM') OR (uname = 'ADSMEM') THEN
    BEGIN
      tk := TK_POINTER;
      aux := TK_CHAR;
    END
    ELSE IF (uname = 'CPTR') OR (uname = 'CCHAR') OR (uname = 'CSHORT') OR
            (uname = 'CINT') OR (uname = 'CLONG') OR (uname = 'CSIZE_T') OR
            (uname = 'CDOUBLE') THEN
    BEGIN
      IF NOT FeaturesAreExtended(active_features) THEN
      BEGIN
        AddError2('Type requires the extended dialect: ', name);
        tk := TK_UNKNOWN;
      END
      ELSE IF uname = 'CPTR' THEN
      BEGIN
        tk := TK_POINTER;
        aux := TK_CHAR;
      END
      ELSE IF uname = 'CCHAR' THEN tk := TK_CHAR
      ELSE IF uname = 'CSHORT' THEN tk := TK_INTEGER
      ELSE IF uname = 'CINT' THEN tk := TK_INTEGER32
      ELSE IF uname = 'CLONG' THEN tk := TK_INTEGER64
      ELSE IF uname = 'CSIZE_T' THEN tk := TK_WORD64
      ELSE tk := TK_REAL;
    END
    ELSE IF uname = 'TEXT' THEN
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
    index_node := GetObj(node, 'index_range');
    bound_node := GetObj(index_node, 'low');
    IF NodeType(bound_node) = 'CharLiteral' THEN idx_tk := TK_CHAR
    ELSE IF NodeType(bound_node) = 'BoolLiteral' THEN idx_tk := TK_BOOLEAN
    ELSE IF NodeType(bound_node) = 'Identifier' THEN
    BEGIN
      bound_si := LookupSymbol(GetStr(bound_node, 'name'));
      IF bound_si <> 0 THEN idx_tk := symbols[bound_si].tk;
    END
    ELSE IF (NodeType(bound_node) = 'IntLiteral') AND
            (GetInt(bound_node, 'value') > 32767) THEN idx_tk := TK_WORD;
    bound_node := GetObjOrNil(index_node, 'high');
    IF bound_node <> NIL THEN
      IF (NodeType(bound_node) = 'IntLiteral') AND
         (GetInt(bound_node, 'value') > 32767) THEN idx_tk := TK_WORD;
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
      uname := UpperStr(name);
      { Same shadowing rule as the NamedType branch above. }
      ti := 0;
      IF GetObjOrNil(node, 'param') = NIL THEN ti := LookupType(name);
      IF ti <> 0 THEN
      BEGIN
        { Copy the whole entry, not just the kind -- the payload fields carry
          an element/base kind (aux), a width or capacity (aux2) and an index
          kind (idx_tk), and dropping them silently loses e.g. an LSTRING
          alias's capacity. Same four assignments as the NamedType branch
          above; that they agree is the point. }
        tk := types[ti].tk;
        aux := types[ti].aux;
        aux2 := types[ti].aux2;
        idx_tk := types[ti].idx_tk;
      END
      ELSE IF uname = 'CHAR' THEN tk := TK_CHAR
      ELSE IF uname = 'BOOLEAN' THEN tk := TK_BOOLEAN
      ELSE IF uname = 'WORD' THEN tk := TK_WORD
      ELSE IF uname = 'INTEGER' THEN tk := TK_INTEGER
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

BEGIN
END.
