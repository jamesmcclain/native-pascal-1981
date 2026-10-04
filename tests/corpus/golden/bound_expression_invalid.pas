{ DIALECT: extended }
PROGRAM BoundExpressionInvalid(output);
TYPE Data = SUPER ARRAY [2..*] OF INTEGER; PData = ^Data;
VAR p: PData;
BEGIN
  WRITELN(UPPER(Data));
  WRITELN(UPPER(p));
  WRITELN(UPPER(1 + 2));
  WRITELN(LOWER('abc'))
END.
