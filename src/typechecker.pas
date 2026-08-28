{ Typechecker composition root and JSON stream driver. }

(*$INCLUDE:'jsonutil.inc'*)
(*$INCLUDE:'tc_base.inc'*)
(*$INCLUDE:'tc_decl.inc'*)
PROGRAM pascal1981_typecheck(input, output);

USES jsonutil, tc_base, tc_decl;

FUNCTION cJSON_Print(item: ADRMEM): ADRMEM [C]; EXTERN;
FUNCTION puts(str: ADRMEM): CINT [C]; EXTERN;
PROCEDURE exit(code: CINT) [C]; EXTERN;

VAR
  root, out_str: ADRMEM;
  i: INTEGER32;
  res_c: CINT;

BEGIN
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
