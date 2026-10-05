{ DIALECT: extended }
{ Real division / between 32-bit and 64-bit integers and words. }
PROGRAM SlashWideIntegers(output);
VAR
  q: INTEGER64;
  u: WORD64;
  d: INTEGER32;
  w: WORD;
  r: REAL;
BEGIN
  q := 10000000000;
  u := 80000000000;
  d := 200000;
  w := 4;

  r := q / 2;
  WRITELN(r:0:2);

  r := u / 4;
  WRITELN(r:0:2);

  r := q / d;
  WRITELN(r:0:2);

  r := u / w;
  WRITELN(r:0:2);

  r := q / w;
  WRITELN(r:0:2)
END.
