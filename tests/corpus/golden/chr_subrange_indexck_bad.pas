{ DIALECT: vintage extended }
{ $INDEXCK guards an ARRAY [CHR(250)..CHR(255)] with the folded bounds:
  index CHR(249) is outside them. }
PROGRAM chr_subrange_indexck_bad(OUTPUT);
VAR a: ARRAY [CHR(250)..CHR(255)] OF INTEGER; ch: CHAR;
BEGIN
  ch := CHR(249); WRITELN('before'); a[ch] := 1; WRITELN('not reached')
END.
