{ DIALECT: extended }
PROGRAM VarargsArityNonVariadic(OUTPUT);
{ The [VARARGS] arity relaxation must apply ONLY to a routine that actually
  carries the attribute: a plain [C] EXTERN still requires an exact match
  between actual and formal argument counts. }
FUNCTION plain_c(a: CINT): CINT [C]; EXTERN;
VAR
  n: CINT;
BEGIN
  n := plain_c(1, 2);
  WRITELN(n);
END.
