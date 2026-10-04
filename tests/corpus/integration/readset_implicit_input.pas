PROGRAM ReadsetImplicitInput(input, output);
TYPE
  Vowels = SET OF CHAR;
VAR
  word: LSTRING(80);
  vowel_set: Vowels;
BEGIN
  vowel_set := ['a', 'e', 'i', 'o', 'u'];
  READSET(word, vowel_set);
  WRITELN(word);
END.
