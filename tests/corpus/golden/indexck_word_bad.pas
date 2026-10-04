PROGRAM indexck_word_bad(OUTPUT);
VAR a: ARRAY[32768..32769] OF INTEGER; w: WORD;
BEGIN
  w := 32767;
  a[w] := 9
END.
