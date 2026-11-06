{ DIALECT: vintage extended }
{ CMP-22: RANGECK checks a store to a subrange field of a file buffer,
  g^.d := n, before the store; the PUT that would follow never runs. }
PROGRAM FileBufferFieldsRangeck(OUTPUT);
{$RANGECK+}
TYPE
  Rec = RECORD
    a: INTEGER;
    d: 0..9
  END;
VAR
  g: FILE OF Rec;
  n: INTEGER;
BEGIN
  REWRITE(g);
  n := 9;
  g^.d := n;
  WRITELN('stored ', g^.d:1);
  n := n + 1;
  g^.d := n;
  PUT(g);
  WRITELN('not reached')
END.
