{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: SIZEOF exceeds 65535, the largest WORD value at line 13 column 3 }
{ SIZEOF is a WORD (IBM manual). A type of 80000 bytes used to give
  80000 MOD 65536 = 14464 without a diagnostic. }
PROGRAM SizeofWord;
TYPE Buf = ARRAY [1..40000] OF CHAR;
     Big = RECORD a, b: Buf END;
VAR w: WORD;
BEGIN
  w := SIZEOF(Buf);
  WRITELN(w);
  w := 1;
  w := SIZEOF(Big);
  WRITELN(w)
END.
