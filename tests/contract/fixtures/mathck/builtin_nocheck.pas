{$MATHCK+}
PROGRAM NoCheck;
VAR i, j: INTEGER; w: WORD;
BEGIN
  i := -32768; j := 32767; w := 65535;
  WRITELN(ORD(i), ' ', ORD(j), ' ', WRD(i), ' ', WRD(j));
  WRITELN(ODD(i), ' ', ODD(j), ' ', ORD(HIBYTE(i)), ' ', ORD(LOBYTE(j)), ' ',
          ORD(HIBYTE(w)));
  i := 300; j := -1;
  { BYWORD has a RANGECK domain check, but never a MATHCK overflow check. }
  {$RANGECK-}
  WRITELN(BYWORD(i, j), ' ', BYWORD(w, w));
  {$RANGECK+}
  i := -32768;
  WRITELN(FLOAT(i):9:1, ' ', FLOAT(w):8:1);
END.
