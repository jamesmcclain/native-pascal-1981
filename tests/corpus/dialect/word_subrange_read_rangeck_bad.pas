{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-32: $RANGECK checks a READ into a WORD subrange (0..40000) and a
  WORD value parameter of it. The WORD reader reported no status, so the
  READ check was skipped and 40001 was stored. }
PROGRAM WordSubrangeReadRangeckBad(INPUT, OUTPUT);
TYPE
  Big = 0..40000;
VAR
  b: Big;
  w: WORD;

PROCEDURE P(x: Big);
BEGIN
  WRITELN('P ', x)
END;

BEGIN
  READLN(b);
  WRITELN(b);
  w := 40000;
  P(w);
  READLN(b);
  WRITELN('not reached ', b)
END.
