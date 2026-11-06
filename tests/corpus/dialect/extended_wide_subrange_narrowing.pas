{ DIALECT: extended }
{ NEW-32: an INTEGER32 subrange (0..100000) value does not narrow into an
  INTEGER or WORD without RETYPE, as an INTEGER32 does not. }
PROGRAM ExtendedWideSubrangeNarrowing;
VAR
  r: 0..100000;
  i: INTEGER;
  w: WORD;
BEGIN
  i := r;
  w := r
END.
