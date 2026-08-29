{ LSTRING's .LEN field: the leading length byte, a CHAR, readable and
  assignable. Legal in the vintage dialect (IBM Pascal, Aug 1981), so it is
  exercised here rather than under tests/dialect. Covers a plain variable, a
  record field, a type alias, and both parameter modes -- each reaches the
  designator walk by a different route. }
PROGRAM LStringLen(OUTPUT);
TYPE
  Line = LSTRING(20);
  Entry = RECORD
    text: LSTRING(10);
    n: INTEGER;
  END;
VAR
  a: Line;
  e: Entry;

PROCEDURE ShowVar(VAR s: Line);
BEGIN
  WRITELN('var param: ', ORD(s.LEN));
END;

FUNCTION Doubled(s: Line): INTEGER;
BEGIN
  Doubled := ORD(s.LEN) * 2;
END;

BEGIN
  a := 'abcdefg';
  WRITELN('plain: ', ORD(a.LEN));
  WRITELN('value param: ', Doubled(a));
  ShowVar(a);

  e.text := 'abc';
  e.n := ORD(e.text.LEN);
  WRITELN('record field: ', e.n);

  { Assigning the length byte truncates the string in place. }
  a.LEN := CHR(3);
  WRITELN('truncated: ', a, ' (', ORD(a.LEN), ')');

  { Lowercase spelling: identifiers are case-insensitive. }
  WRITELN('lowercase: ', ORD(a.len));
END.
