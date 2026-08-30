{ DIALECT: extended }
PROGRAM ExtendedReadsetLiteral(output);
VAR
  f: TEXT;
  text: LSTRING(8);
BEGIN
  ASSIGN(f, '/tmp/native_pascal_extended_readset_literal.txt');
  REWRITE(f);
  WRITELN(f, 'abc123');
  CLOSE(f);
  RESET(f);
  READSET(f, text, ['a'..'z']);
  WRITELN(text);
  CLOSE(f)
END.
