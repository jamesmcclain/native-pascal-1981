{ DIALECT: extended }
{ NEW-36: CHR(0) is rejected in `*` string constant concatenation because
  C-string AST literals cannot carry an embedded NUL byte. }
PROGRAM ConstStringConcatNull(OUTPUT);
CONST
  BAD = 'a' * CHR(0) * 'b';
BEGIN
  WRITELN(BAD);
END.
