{ DIALECT: extended }
PROGRAM BoundExpressionSuperValue(output);
TYPE Data = SUPER ARRAY [2..*] OF INTEGER;
VAR data_var: Data;
BEGIN
  WRITELN(UPPER(data_var))
END.
