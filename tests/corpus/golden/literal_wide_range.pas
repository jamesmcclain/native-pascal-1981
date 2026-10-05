{ DIALECT: extended }
{ A literal wider than WORD keeps its own type in an expression. }
PROGRAM LiteralWideRange(output);
CONST BIG = 5000000000;
VAR i: INTEGER; l: INTEGER32; d: WORD32; q: INTEGER64; u: WORD64;
BEGIN
  WRITELN(70000, ' ', -70000, ' ', 4294967295, ' ', 2147483648);
  i := -1; l := -1; d := 70000;
  WRITELN(i < 70000, ' ', l < 40000, ' ', d = 70000, ' ', d < 4294967295);
  WRITELN(l + 70000, ' ', d + 40000);
  { Beyond WORD32 a literal is INTEGER64, not an out-of-range WORD32. }
  q := 1; u := 1; d := 1;
  WRITELN(4294967296, ' ', q + 4294967296, ' ', u + 4294967296, ' ', l + 4294967296);
  WRITELN(d + 4294967296, ' ', d + BIG, ' ', u > 4294967296, ' ', q < 4294967296)
END.
