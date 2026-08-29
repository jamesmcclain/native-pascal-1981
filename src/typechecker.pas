{ Typechecker composition root and JSON stream driver. }

(*$INCLUDE:'argparse.inc'*)
(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_decl.inc'*)
PROGRAM pascal1981_typecheck(input, output);

USES argparse, jsonutil, tc_base, tc_decl;

FUNCTION cJSON_Print(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION puts(str: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;

VAR
  root, out_str: ADRMEM;
  i: INTEGER32;
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
  ArgBegin('typechecker', 'Pascal-1981 typechecker stage.');
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
    EPrint('error: typechecker accepts input only on standard input');
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
  TcInit;
  root := ReadAllStdin;
  CheckRoot(root);

  IF nerrors > 0 THEN
  BEGIN
    EPrint('Type checking failed:');
    FOR i := 1 TO nerrors DO
      EPrint(errors[i]);
    exit(1);
  END;

  out_str := cJSON_Print(root);
  res_c := puts(out_str);
END.
