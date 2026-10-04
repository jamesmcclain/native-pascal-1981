PROGRAM disabledwrites;
PROCEDURE probe(take: BOOLEAN);
{$INITCK+}
VAR x, y: INTEGER; b: BOOLEAN; c: CHAR;
BEGIN
  {$INITCK-}
  IF take THEN BEGIN x := 0; b := FALSE; c := 'a' END
  ELSE BEGIN x := -32768; b := TRUE; c := 'z' END;
  y := x;
  {$INITCK+} WRITELN(x, ':', y, ':', ORD(b), ':', c);
  {$INITCK-} x := x + 1; y := x; b := NOT b; c := 'q';
  {$INITCK+} WRITELN(x, ':', y, ':', ORD(b), ':', c)
  {$INITCK-}
END;
BEGIN probe(TRUE); probe(FALSE); probe(TRUE) END.
