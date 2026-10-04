PROGRAM CValue(output);
VAR c: CINT;
FUNCTION abs(x: CINT): CINT [C]; EXTERN;
BEGIN
  c := abs(-2147483647);
  WRITELN('prefix');
  WRITELN(c + 1)
END.
