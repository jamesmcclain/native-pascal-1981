{ DIALECT: vintage extended }
{ NEW-21: a string CONST is a literal, not storage or a number: it takes
  no selector, has no declared capacity for UPPER, and is not an integer,
  an ordinal or a STRING capacity. Each is a type error. }
PROGRAM StringConstantMisuse(OUTPUT);
CONST
  S = 'abc';
VAR
  i: INTEGER;
  t: STRING(S);
BEGIN
  WRITELN(S[1]);
  WRITELN(UPPER(S));
  i := S;
  WRITELN(ORD(S))
END.
