PROGRAM SetAnonymousBounds(OUTPUT);
{ Semantic hosts constrain compatibility, not the bounds of anonymous sets. }
TYPE BS = SET OF BOOLEAN; CS = SET OF CHAR;
     I1 = SET OF 3..9; I2 = SET OF 1..5;
VAR bs: BS; cs: CS; a: I1; b: I2; flag: BOOLEAN; ch: CHAR; n: INTEGER;
FUNCTION GetBS: BS;
BEGIN GetBS := bs END;
BEGIN
  bs := [TRUE]; cs := ['A']; a := [3]; b := [5];
  WRITELN(LOWER([TRUE]), ' ', UPPER([TRUE]), ' ',
          LOWER(['A']), ' ', UPPER(['A']), ' ',
          LOWER([]), ' ', UPPER([]));
  WRITELN(LOWER(bs), ' ', UPPER(bs), ' ',
          ORD(LOWER(cs)), ' ', ORD(UPPER(cs)));
  WRITELN(LOWER(bs + []), ' ', UPPER(bs + []), ' ',
          LOWER([] + bs), ' ', UPPER([] + bs), ' ',
          LOWER(bs * []), ' ', UPPER(bs - []));
  WRITELN(LOWER(bs + [TRUE]), ' ', UPPER([FALSE] + bs), ' ',
          LOWER((bs + []) + GetBS), ' ', UPPER(GetBS + (bs * [])));
  WRITELN(LOWER(cs + []), ' ', UPPER([] + cs), ' ',
          LOWER(cs + ['B']), ' ', UPPER(['A'] * cs));
  WRITELN(LOWER(a + b), ' ', UPPER(a + b), ' ',
          LOWER(a * b), ' ', UPPER(a - b), ' ',
          LOWER(a + []), ' ', UPPER([] + b));
  flag := UPPER(bs); ch := LOWER(cs); n := UPPER(bs + []);
  WRITELN(flag, ' ', ORD(ch), ' ', n, ' ', bs = [], ' ', [] = bs)
END.
