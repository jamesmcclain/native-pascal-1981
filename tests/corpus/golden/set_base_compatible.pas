PROGRAM SetBaseCompatible(OUTPUT);
CONST Five = 5; Letter = 'A'; Yes = TRUE;
TYPE Num = 1..5;
     Nums = SET OF 1..5;
     NumAlias = Nums;
     NamedNums = SET OF Num;
     MoreNums = SET OF 3..9;
     CharRange = 'A'..'Z';
     Chars = SET OF CHAR;
     CharAlias = Chars;
     NarrowChars = SET OF CharRange;
     BoolRange = FALSE..TRUE;
     Bools = SET OF BOOLEAN;
     NarrowBools = SET OF BoolRange;
VAR a: Nums; b: NumAlias; c: MoreNums; d: NamedNums;
    cs: Chars; ca: CharAlias; nc: NarrowChars;
    bs: Bools; nb: NarrowBools; n: Num; letterVar: CHAR; flag: BOOLEAN;
FUNCTION NextNum: INTEGER;
BEGIN NextNum := Five END;
FUNCTION NextChar: CHAR;
BEGIN NextChar := Letter END;
FUNCTION NextBool: BOOLEAN;
BEGIN NextBool := Yes END;
BEGIN
  n := 3;
  a := [n, Five, NextNum];
  b := [3..Five];
  c := a + b;
  d := a;
  WRITELN('integer ', 3 IN c, ' ', 1 IN c, ' ', 10 IN c,
          ' ', a <= c, ' ', c >= b, ' ', a * [] = [],
          ' ', [] = a - a, ' ', (a + []) - [] = a);
  letterVar := 'B';
  cs := [Letter, letterVar, NextChar];
  ca := cs + [];
  nc := ca;
  WRITELN('char ', Letter IN ca, ' ', 'B' IN ca,
          ' ', (cs * ca) = cs, ' ', [] <> ca);
  flag := FALSE;
  bs := [flag, Yes, NextBool];
  nb := bs;
  WRITELN('named subranges ', d = a, ' ', nc = cs, ' ', nb = bs);
  WRITELN('boolean ', FALSE IN bs, ' ', TRUE IN bs,
          ' ', bs = [FALSE, TRUE], ' ', [] + bs = bs,
          ' ', bs - bs = [], ' ', bs <> [])
END.
