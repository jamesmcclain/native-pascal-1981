{ Pascal-1981 Native Parser implementation in extended IBM Pascal 2.0 dialect. }

(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'ps_base.inc'*)
(*$INCLUDE:'ps_expr.inc'*)
(*$INCLUDE:'ps_stmt.inc'*)
(*$INCLUDE:'ps_decl.inc'*)
PROGRAM pascal1981_parse(input, output);

USES argparse, jsonutil, ps_base, ps_expr, ps_stmt, ps_decl;


VAR
  ast_root, json_out, interfaces_arr, iface_node, local_ifaces_arr: ADRMEM;
  cand_iface, iface_name_field, unit_type_field, matched_iface: ADRMEM;
  standalone_iface: BOOLEAN;
  n_ifaces, rc: CINT;
  ii: INTEGER32;
  res_c: CINT;
  dialect_arg, arg_error: ArgStr;

PROCEDURE PrintArgError;
VAR
  msg: Str255;
  i, n: INTEGER32;
BEGIN
  ArgError(arg_error);
  n := ORD(arg_error[0]);
  msg[0] := CHR(RETYPE(INTEGER, n));
  i := 1;
  WHILE i <= n DO
  BEGIN
    msg[i] := arg_error[i];
    i := i + 1;
  END;
  EPrint(msg);
END;

PROCEDURE ParseArgs;
BEGIN
  ArgBegin('parser', 'Pascal-1981 parser stage.');
  ArgString('dialect', ARG_NO_SHORT, 'vintage',
            'Language dialect: vintage or extended.');
  IF NOT ArgParse THEN
  BEGIN
    IF ArgHelpWanted THEN exit(0);
    PrintArgError;
    exit(1);
  END;
  IF ArgPosCount <> 0 THEN
  BEGIN
    EPrint('error: parser accepts input only on standard input');
    exit(1);
  END;
  ArgGetStr('dialect', dialect_arg);
  IF (dialect_arg <> 'vintage') AND (dialect_arg <> 'extended') THEN
  BEGIN
    EPrint('error: invalid dialect; expected ''vintage'' or ''extended''');
    exit(1);
  END;
END;

BEGIN
  ParseArgs;
  pos := 0;
  expr_depth := 0;
  stmt_depth := 0;
  ReadInputAndParseTokens;

  interfaces_arr := cJSON_CreateArray;
  standalone_iface := FALSE;

  WHILE (NOT standalone_iface) AND ((CurKind = 'INTERFACE') OR IsAtDevicePrefix('INTERFACE')) DO
  BEGIN
    IF CurKind = 'INTERFACE' THEN
      iface_node := ParseInterfaceUnit(FALSE)
    ELSE
    BEGIN
      pos := pos + 1;
      iface_node := ParseInterfaceUnit(TRUE);
    END;
    cJSON_AddItemToArray(interfaces_arr, iface_node);
    IF CurKind = 'EOF' THEN
    BEGIN
      standalone_iface := TRUE;
      ast_root := cJSON_GetArrayItem(interfaces_arr, 0);
    END;
  END;

  IF NOT standalone_iface THEN
  BEGIN
    IF CurKind = 'PROGRAM' THEN
      ast_root := ParseProgramUnit
    ELSE IF CurKind = 'MODULE' THEN
      ast_root := ParseModuleUnit(FALSE)
    ELSE IF IsAtDevicePrefix('MODULE') THEN
    BEGIN
      pos := pos + 1;
      ast_root := ParseModuleUnit(TRUE);
    END
    ELSE IF CurKind = 'INTERFACE' THEN
      ast_root := ParseInterfaceUnit(FALSE)
    ELSE IF IsAtDevicePrefix('INTERFACE') THEN
    BEGIN
      pos := pos + 1;
      ast_root := ParseInterfaceUnit(TRUE);
    END
    ELSE IF CurKind = 'IMPLEMENTATION' THEN
      ast_root := ParseImplementationUnit(FALSE)
    ELSE IF IsAtDevicePrefix('IMPLEMENTATION') THEN
    BEGIN
      pos := pos + 1;
      ast_root := ParseImplementationUnit(TRUE);
    END
    ELSE
    BEGIN
      EPrint('Parser Error: expected compilation unit start');
      exit(1);
    END;

    { Wire up any spliced leading INTERFACE header(s): attach a duplicate of
      each to local_interfaces (present on ProgramUnit/ModuleUnit/
      ImplementationUnit), and for an ImplementationUnit, transfer ownership
      of the name-matching one into its 'interface' field. }
    n_ifaces := cJSON_GetArraySize(interfaces_arr);
    IF n_ifaces > 0 THEN
    BEGIN
      unit_type_field := cJSON_GetObjectItem(ast_root, MakeCStr('__node_type__'));
      local_ifaces_arr := cJSON_GetObjectItem(ast_root, MakeCStr('local_interfaces'));
      matched_iface := NIL;
      FOR ii := 0 TO n_ifaces - 1 DO
      BEGIN
        cand_iface := cJSON_GetArrayItem(interfaces_arr, ii);
        IF local_ifaces_arr <> NIL THEN
          cJSON_AddItemToArray(local_ifaces_arr, cJSON_Duplicate(cand_iface, 1));
        IF (matched_iface = NIL) AND
           StringEqual(CStrToStr255(cJSON_GetStringValue(unit_type_field)), 'ImplementationUnit') THEN
        BEGIN
          iface_name_field := cJSON_GetObjectItem(cand_iface, MakeCStr('name'));
          IF StringEqual(UpperStr(CStrToStr255(cJSON_GetStringValue(iface_name_field))),
                          UpperStr(CStrToStr255(cJSON_GetStringValue(
                            cJSON_GetObjectItem(ast_root, MakeCStr('name')))))) THEN
            matched_iface := cand_iface;
        END;
      END;
      IF matched_iface <> NIL THEN
      BEGIN
        FOR ii := 0 TO n_ifaces - 1 DO
          IF cJSON_GetArrayItem(interfaces_arr, ii) = matched_iface THEN
          BEGIN
            matched_iface := cJSON_DetachItemFromArray(interfaces_arr, ii);
            BREAK;
          END;
        rc := cJSON_ReplaceItemInObject(ast_root, MakeCStr('interface'), matched_iface);
      END;
    END;
    cJSON_Delete(interfaces_arr);
  END;

  json_out := cJSON_Print(ast_root);
  res_c := puts(json_out);
  free(json_out);
  cJSON_Delete(ast_root);
  free(tokens_buf);
END.
