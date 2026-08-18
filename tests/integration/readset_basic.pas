PROGRAM ReadsetBasic(output);
TYPE
  Vowels = SET OF CHAR;
VAR
  f: TEXT;
  word: LSTRING(80);
  vowel_set: Vowels;
BEGIN
  ASSIGN(f, '/tmp/native_pascal_test_readset_basic.txt');
  REWRITE(f);
  WRITELN(f, 'aeiouXYZ');
  CLOSE(f);

  RESET(f);
  vowel_set := ['a', 'e', 'i', 'o', 'u'];
  READSET(f, word, vowel_set);
  WRITELN(word);
  CLOSE(f);
END.
