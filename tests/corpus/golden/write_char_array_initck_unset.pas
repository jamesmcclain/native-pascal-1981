{$INITCK+}
PROGRAM write_char_array_initck_unset(OUTPUT);
{ Under INITCK, WRITE of a whole CHAR array reads every component: one
  never assigned is caught at the WRITE, after the earlier output. }
TYPE T = ARRAY [1..3] OF CHAR;
PROCEDURE q;
VAR a, b: T;
BEGIN
  a[1] := 'h'; a[2] := 'i'; a[3] := '!';
  WRITELN(a);
  b[1] := 'n'; b[3] := 'o';
  WRITELN(b:5)
END;
BEGIN q END.
