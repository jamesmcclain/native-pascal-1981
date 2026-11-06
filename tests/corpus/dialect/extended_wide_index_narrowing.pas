{ DIALECT: extended }
{ NEW-5: LOWER and UPPER of an INTEGER32 index range are INTEGER32, so
  they do not narrow into an INTEGER or WORD without RETYPE. }
PROGRAM ExtendedWideIndexNarrowing;
VAR
  a: ARRAY [0..70000] OF CHAR;
  i: INTEGER;
  w: WORD;
BEGIN
  i := UPPER(a);
  w := LOWER(a)
END.
