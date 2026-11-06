{ DIALECT: extended }
{ OPT: 0 2 }
{ NEW-32: $RANGECK checks a store into an INTEGER32 subrange (0..100000)
  at full width: the INTEGER32 100001 is outside it. }
PROGRAM ExtendedWideSubrangeRangeckBad(OUTPUT);
VAR
  r: 0..100000;
  i32: INTEGER32;
BEGIN
  i32 := 100001; r := 100000; WRITELN(r); r := i32; WRITELN('not reached')
END.
