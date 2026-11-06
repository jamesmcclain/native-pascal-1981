{ DIALECT: vintage extended }
{ CMP-22: under INITCK, GET initializes the whole record buffer, so its
  fields read fine; after REWRITE the buffer is undefined again and a read
  of a field that was not written fails, naming the leaf. }
PROGRAM FileBufferFieldsInitckRead(OUTPUT);
{$INITCK+}
TYPE
  Rec = RECORD
    a: INTEGER;
    b: ARRAY [1..2] OF INTEGER
  END;

PROCEDURE Run;
VAR
  g: FILE OF Rec;
BEGIN
  REWRITE(g);
  g^.a := 1;
  g^.b[1] := 2;
  g^.b[2] := 3;
  PUT(g);
  RESET(g);
  WRITELN('read ', g^.a:1, ' ', g^.b[1]:1, ' ', g^.b[2]:1);
  REWRITE(g);
  g^.a := 7;
  WRITELN('a ', g^.a:1);
  WRITELN(g^.b[2]:1);
  WRITELN('not reached')
END;

BEGIN
  Run
END.
