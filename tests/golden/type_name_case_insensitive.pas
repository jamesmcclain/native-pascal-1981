PROGRAM TypeNameCaseInsensitive(output);

{ "Lowercase and uppercase letters are interchangeable, except in string
  literals" -- IBM Pascal, Aug 1981, Syntax and Vocabulary. That covers
  identifiers, so a type name resolves regardless of how it is spelled:
  predeclared names, user TYPE names, the name at its own declaration, the
  base of a SET OF, and a RETYPE target all fold the same way. }

TYPE
  MixedRec = RECORD
    a: integer;
    b: Real;
  END;
  CharSet = set of Char;

VAR
  x: integer;
  y: rEaL;
  c: char;
  r: mixedrec;
  s: CHARSET;
  w: Word;

BEGIN
  x := 3;
  y := 1.5;
  c := 'q';
  r.a := x;
  r.b := y;
  s := ['q'];
  w := RETYPE(word, x);
  IF c IN s THEN
    WRITELN('in set');
  WRITELN(r.a, ' ', r.b:0:2, ' ', c, ' ', w);
END.
