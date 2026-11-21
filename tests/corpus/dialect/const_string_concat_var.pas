{ DIALECT: vintage extended }
{ NEW-36: IBM manual 5-10 -- `*` string concatenation only works with
  string/CHAR constants, not string variables. }
PROGRAM ConstStringConcatVar(OUTPUT);
VAR
  s: STRING(4);
BEGIN
  s := 'abcd';
  WRITELN(s * 'e');
END.
