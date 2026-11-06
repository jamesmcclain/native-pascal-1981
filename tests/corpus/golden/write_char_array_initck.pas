{$INITCK+}
{ DIALECT: vintage extended }
PROGRAM write_char_array_initck(OUTPUT);
{ Under INITCK, WRITE of a wholly initialized CHAR array passes the strict
  whole-value check through a local, a VAR and a value formal, a record
  field and a WITH-bound field. }
TYPE T = ARRAY [1..2] OF CHAR;
     R = RECORD t: T; n: INTEGER END;
PROCEDURE v(VAR x: T);
BEGIN WRITELN(x, x:3) END;
PROCEDURE c(x: T);
BEGIN WRITELN(x) END;
PROCEDURE q;
VAR a: T; r: R;
BEGIN
  a[1] := 'o'; a[2] := 'k';
  v(a); c(a);
  r.t := a;
  WITH r DO WRITELN(t);
  WITH r DO BEGIN t[1] := 'x'; WRITELN(t) END;
  r.n := 0;
  WRITELN(r.t, r.n:2)
END;
BEGIN q END.
