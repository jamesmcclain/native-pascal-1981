{ DIALECT: vintage extended }
{ NEW-36: IBM manual 5-10 -- concatenated string constants are limited to
  255 characters. }
PROGRAM ConstStringConcatTooLong(OUTPUT);
CONST
  S64 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  S256 = S64 * S64 * S64 * S64;
BEGIN
  WRITELN(S256);
END.
