{ DIALECT: vintage }
{ A literal in 32768..65535 is a WORD constant, not a wrapped INTEGER. }
PROGRAM LiteralWordRange(output);
VAR i: INTEGER; w: WORD;
BEGIN
  WRITELN(40000, ' ', 65535, ' ', 32768);
  i := -1; w := 1;
  WRITELN(i < 40000, ' ', 40000 > i, ' ', i = 65535, ' ', w < 40000);
  WRITELN(w + 40000, ' ', 65535 - w);
  w := 65535;
  IF w = 65535 THEN WRITELN('max')
END.
