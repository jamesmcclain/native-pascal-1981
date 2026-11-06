{ DIALECT: extended }
{ OPT: 0 2 }
{ NEW-32: $RANGECK checks a READ into an INTEGER32 subrange (0..100000).
  The INTEGER32 reader reported no status, so the check was skipped. }
PROGRAM ExtendedWideSubrangeReadRangeckBad(INPUT, OUTPUT);
VAR
  r: 0..100000;
BEGIN
  READLN(r);
  WRITELN(r);
  READLN(r);
  WRITELN('not reached ', r)
END.
