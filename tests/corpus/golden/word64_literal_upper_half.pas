{ DIALECT: extended }
{ WORD64 literals of 2^63 and above. The lexer accumulated every literal
  in a MATHCK-checked INTEGER64, so 9223372036854775808 crashed the
  compiler itself with a signed overflow. Such a literal is now a WORD64
  operand, in decimal or radix form, as a CONST, a CASE label and an
  array element; -9223372036854775808 is the INTEGER64 minimum. }
PROGRAM word64_literal_upper_half(OUTPUT);
CONST
  BIG = 18446744073709551615;
  SAME = BIG;
  MIN64 = -9223372036854775808;
VAR
  w: WORD64;
  i: INTEGER64;
  a: ARRAY [1..2] OF WORD64;
BEGIN
  w := 9223372036854775808; WRITELN(w);
  w := 18446744073709551615; WRITELN(w);
  w := 16#FFFFFFFFFFFFFFFF; WRITELN(w = BIG);
  w := 16#8000000000000001; WRITELN(w);
  WRITELN(SAME);
  i := MIN64; WRITELN(i);
  i := -9223372036854775808; WRITELN(i);
  i := 9223372036854775807; WRITELN(i);
  a[1] := 9223372036854775809; a[2] := BIG;
  WRITELN(a[1] < a[2], ' ', a[2] - a[1]);
  WRITELN(BIG DIV 10, ' ', BIG MOD 10);
  w := 18446744073709551614; w := w + 1; WRITELN(w);
  CASE w OF
    9223372036854775808: WRITELN('low');
    18446744073709551615: WRITELN('max')
  OTHERWISE WRITELN('none')
  END
END.
