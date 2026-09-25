{ DIALECT: extended }
PROGRAM BoundExpressionNilField(output);
TYPE Data = SUPER ARRAY [2..*] OF INTEGER; PData = ^Data;
     Holder = RECORD data: PData END;
VAR h: Holder;
BEGIN
  h.data := NIL;
  WRITELN(LOWER(h.data^));
  WRITELN(UPPER(h.data^))
END.
