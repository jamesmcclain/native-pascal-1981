{ DIALECT: vintage extended }
{ CMP-22: under INITCK a field store initializes only its own leaf of the
  file buffer. Reading a stored field is fine; PUT consumes the whole
  component and fails while a leaf is still unwritten. }
PROGRAM FileBufferFieldsInitckPut(OUTPUT);
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
  WRITELN('first put');
  g^.a := 4;
  g^.b[1] := 5;
  WRITELN('b[1] ', g^.b[1]:1);
  PUT(g);
  WRITELN('not reached')
END;

BEGIN
  Run
END.
