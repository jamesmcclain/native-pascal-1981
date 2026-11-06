{ DIALECT: vintage extended }
{ $RANGECK checks a store into a CHR(250)..CHR(255) subrange against the
  folded bounds: CHR(249) is outside them. }
PROGRAM chr_subrange_rangeck_bad(OUTPUT);
TYPE Tail = CHR(250)..CHR(255);
VAR c: Tail; ch: CHAR;
BEGIN
  ch := CHR(249); WRITELN('before'); c := ch; WRITELN('not reached')
END.
