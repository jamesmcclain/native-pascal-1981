PROGRAM TypeNameCaseInsensitive(output);

{ "Lowercase and uppercase letters are interchangeable, except in string
  literals" -- IBM Pascal, Aug 1981, Syntax and Vocabulary -- so a predeclared
  type name resolves however it is spelled, including as a SET OF base and as
  a RETYPE target. User-declared type names fold too; that half lives in
  tests/golden/type_name_case_insensitive.pas because the Python reference
  still matches its own symbol table case-sensitively. }

VAR
  x: integer;
  y: rEaL;
  c: Char;
  s: set of CHAR;
  w: Word;

BEGIN
  x := 3;
  y := 1.5;
  c := 'q';
  s := ['q'];
  w := RETYPE(word, x);
  IF c IN s THEN
    WRITELN('in set');
  WRITELN(x, ' ', y:0:2, ' ', c, ' ', w);
END.
