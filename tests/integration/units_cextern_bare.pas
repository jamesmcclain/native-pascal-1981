(*$INCLUDE:'units_cextern_bare.cbare.inc'*)
PROGRAM UnitsCExternBare(output);
USES cbare;
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
