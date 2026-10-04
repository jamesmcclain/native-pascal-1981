{ A function returning Str255 by value, assigned from a literal, from a
  local, and from another call; records passed by value and by VAR. }
(*$INCLUDE:'testio.inc'*)
PROGRAM str255_result(input, output);
USES testio;

TYPE
  Named = RECORD
    name: Str255;
    id: INTEGER32;
  END;

FUNCTION Greeting(polite: BOOLEAN): Str255;
VAR
  s: Str255;
BEGIN
  IF polite THEN
    Greeting := 'good day'
  ELSE
  BEGIN
    s := 'hey';
    Greeting := s;
  END;
END;

FUNCTION Twice(s: Str255): Str255;
VAR
  r: Str255;
BEGIN
  r := s;
  CONCAT(r, s);
  Twice := r;
END;

PROCEDURE Rename(VAR n: Named; s: Str255);
BEGIN
  n.name := s;
  n.id := n.id + 1;
END;

FUNCTION IdOf(n: Named): INTEGER32;
BEGIN
  n.id := 0;
  IdOf := n.id;
END;

VAR
  n: Named;

BEGIN
  WriteStr(Greeting(TRUE));
  WRITELN;
  WriteStr(Twice(Greeting(FALSE)));
  WRITELN;
  n.name := 'first';
  n.id := 10;
  Rename(n, Twice('ab'));
  WriteLabel('renamed');
  WriteStr(n.name);
  WRITE(' ');
  WriteInt(n.id);
  WRITE(' ');
  WriteInt(IdOf(n));
  WRITE(' ');
  WriteInt(n.id);
  WRITELN;
END.
