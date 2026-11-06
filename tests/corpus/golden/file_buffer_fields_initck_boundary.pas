{ CMP-22: a file buffer whose component has an untracked leaf (REAL) is
  the INITCK `file buffer` boundary: an enabled read of any of its fields
  is a compile error, never an unchecked pass. Stores are allowed. }
PROGRAM FileBufferFieldsInitckBoundary(OUTPUT);
{$INITCK+}
TYPE
  Rec = RECORD
    a: INTEGER;
    x: REAL
  END;

PROCEDURE Run;
VAR
  g: FILE OF Rec;
BEGIN
  REWRITE(g);
  g^.a := 1;
  g^.x := 1.5;
  WRITELN(g^.a:1)
END;

BEGIN
  Run
END.
