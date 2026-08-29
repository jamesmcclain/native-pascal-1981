{ DIALECT: extended }
(*$INCLUDE:'units_cextern.cwrap.inc'*)
PROGRAM UnitsCExtern(output);
USES cwrap;
VAR
  t: Tag;
BEGIN
  Bump;
  Bump;
  Bump;
  WRITELN(Tally);
  t := 'abcde';
  WRITELN(TagLen(t));
  WRITELN(Magnitude(-42));
  WRITELN(Magnitude(17));
END.
