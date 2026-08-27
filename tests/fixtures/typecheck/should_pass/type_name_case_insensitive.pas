PROGRAM IdentifierCaseInsensitive(output);

{ "Lowercase and uppercase letters are interchangeable, except in string
  literals" -- IBM Pascal, Aug 1981, Syntax and Vocabulary. Type, variable,
  procedure, and function identifiers therefore resolve in any case. }

TYPE
  MixedRec = RECORD
    a: integer;
    b: Real;
  END;
  CharSet = set of Char;

VAR
  Counter: integer;
  y: rEaL;
  c: char;
  r: mixedrec;
  s: CHARSET;
  w: Word;

PROCEDURE Greet;
BEGIN
  counter := COUNTER + 1;
END;

FUNCTION DoubleIt(number: INTEGER): INTEGER;
BEGIN
  DoubleIt := number * 2;
END;

BEGIN
  counter := 3;
  y := 1.5;
  c := 'q';
  r.a := COUNTER;
  r.b := y;
  s := ['q'];
  w := RETYPE(word, counter);
  greet;
  Counter := DOUBLEIT(counter);
  IF c IN s THEN
    WRITELN('in set');
  WRITELN(r.a, ' ', r.b:0:2, ' ', c, ' ', w, ' ', COUNTER);
END.
