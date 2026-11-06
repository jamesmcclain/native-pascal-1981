{ DIALECT: extended }
{ NEW-24: LOWER and UPPER of a string whose capacity exceeds 65535 are
  INTEGER32, so they do not narrow into a WORD or INTEGER without RETYPE. }
PROGRAM ExtendedWideStringBoundNarrowing(OUTPUT);
VAR
  h: LSTRING(70000);
  w: WORD;
  i: INTEGER;
BEGIN
  w := UPPER(h);
  i := LOWER(h)
END.
