(*$INCLUDE:'unit_string_const.inc'*)
{ NEW-21: a multi-character string CONST exported from a unit is the same
  literal in the program that uses it. }
PROGRAM UnitStringConst(output);
USES stringconstunit;
BEGIN
  Show;
  WRITELN(Greeting);
END.
