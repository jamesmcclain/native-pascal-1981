{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ REAL literals reach the binary with their exact IEEE-754 bits. Each
  stage passes the AST on as JSON, and cJSON printed a double with only
  15 significant digits, so a literal that needs 16 or 17 shifted between
  stages (1.7976931348623157E308 even became infinity), and the lexer and
  parser built the value digit by digit in REAL arithmetic, which was off
  by ulps. Every literal here is compared with the same value built by
  exact arithmetic on powers of two. }
PROGRAM real_literal_exact_bits(OUTPUT);
CONST
  MAXR = 1.7976931348623157E308;
  NEGMIN = -2.2250738585072014E-308;
VAR
  p, ulp, big: REAL;
  i: INTEGER;
BEGIN
  { 0.1 + 0.2 and the next double above 0.1 }
  WRITELN(0.30000000000000004 = 0.1 + 0.2);
  WRITELN(0.3 <> 0.1 + 0.2);
  ulp := 1.0;
  FOR i := 1 TO 56 DO ulp := ulp / 2.0;
  WRITELN(0.10000000000000002 = 0.1 + ulp);
  WRITELN(0.10000000000000002 <> 0.1);

  { 2^-1022, the smallest normal double, and 2^-1074, the smallest
    subnormal }
  p := 1.0;
  FOR i := 1 TO 1022 DO p := p / 2.0;
  WRITELN(2.2250738585072014E-308 = p);
  WRITELN(NEGMIN = -p);
  FOR i := 1 TO 52 DO p := p / 2.0;
  WRITELN(4.9406564584124654E-324 = p);
  WRITELN(5.0E-324 = p);

  { (2 - 2^-52) * 2^1023, the largest double }
  ulp := 1.0;
  FOR i := 1 TO 52 DO ulp := ulp / 2.0;
  big := 2.0 - ulp;
  FOR i := 1 TO 1023 DO big := big * 2.0;
  WRITELN(1.7976931348623157E308 = big);
  WRITELN(MAXR = big);

  { Integers beyond 2^53 round to even }
  p := 1.0;
  FOR i := 1 TO 53 DO p := p * 2.0;
  WRITELN(9007199254740993.0 = p);
  WRITELN(9007199254740995.0 = p + 4.0);
  WRITELN(9007199254740992.5E0 = p)
END.
