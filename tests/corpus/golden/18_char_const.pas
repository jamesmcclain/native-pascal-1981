PROGRAM char_const(input, output);
{ A CONST may be a character literal, not only an integer or a real. The value
  is folded to its ordinal like any other constant, so numeric uses such as
  ORD keep working, but it is remembered as a CHAR so that WRITELN prints the
  character rather than its ordinal, and so that comparison and assignment
  against a CHAR variable typecheck. A CONST defined as another CHAR CONST
  inherits the same treatment. }
CONST
  SPACE    = ' ';
  BANG     = '!';
  LETTER_A = 'A';
  ALIAS    = LETTER_A;
  COUNT    = 5;
VAR
  c: CHAR;
BEGIN
  c := LETTER_A;
  WRITELN(c, SPACE, BANG);
  WRITELN('alias=', ALIAS);
  WRITELN('ord=', ORD(SPACE));
  WRITELN('eq=', c = LETTER_A);
  WRITELN('ne=', c = BANG);
  c := SPACE;
  WRITELN('assigned=[', c, ']');
  { An integer CONST in the same block is unaffected. }
  WRITELN('int=', COUNT * 2);
END.
