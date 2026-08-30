PROGRAM VintageShadowInteger32(OUTPUT);
TYPE
  INTEGER32 = RECORD
    payload: INTEGER;
  END;
VAR
  n: INTEGER32;
BEGIN
  n.payload := 7;
  WRITELN(n.payload)
END.
