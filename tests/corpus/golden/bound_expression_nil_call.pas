{ DIALECT: extended }
PROGRAM BoundExpressionNilCall(output);
TYPE Data = SUPER ARRAY [2..*] OF INTEGER; PData = ^Data;
VAR p: PData; calls: INTEGER;
FUNCTION get(n: INTEGER): PData;
BEGIN calls := calls + 1; get := p END;
BEGIN
  p := NIL;
  WRITELN(LOWER(get(1)^), ' ', calls);
  WRITELN(UPPER(get(1)^))
END.
