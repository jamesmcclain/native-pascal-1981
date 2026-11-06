{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-32: $RANGECK checks a store into a WORD subrange (0..40000) as
  unsigned: the WORD 40001 is outside it and is reported as 40001, not as
  a negative INTEGER. }
PROGRAM WordSubrangeRangeckBad(OUTPUT);
VAR
  b: 0..40000;
  w: WORD;
BEGIN
  w := 40001; b := 40000; WRITELN(b); b := w; WRITELN('not reached')
END.
