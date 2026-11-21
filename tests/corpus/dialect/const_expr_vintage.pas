{ DIALECT: vintage extended }
{ NEW-36: Vintage CONST expressions (IBM manual 5-9..5-10) -- integer/WORD
  arithmetic, parentheses, unary sign, boolean and relational ops, constant
  functions, subrange/array/STRING/CASE constant expressions, and `*` string
  constant concatenation. }
PROGRAM ConstExprVintage(OUTPUT);
CONST
  BASE = 10;
  ARITH = (BASE + 5) * 3 - 8 DIV 2 + 7 MOD 4;
  NEGMUL = -2 * 3;
  WORDSUM = WRD(100) + BYWORD(1, 2);
  HI = HIBYTE(WORDSUM);
  LO = LOBYTE(WORDSUM);
  ABSV = ABS(-17);
  SQRV = SQR(6);
  B1 = (BASE > 5) AND NOT (BASE = 0);
  B2 = (BASE < 5) OR (BASE >= 10);
  B3 = (BASE = 10) XOR (BASE <> 10);
  HEADER = 'Now''s the time';
  GREET = HEADER * ' ' * 'for all' * '!';
  PAIR = 'A' * 'B';
TYPE
  Sub = BASE + 1 .. BASE * 2;
  Arr = ARRAY [0 .. BASE - 1] OF INTEGER;
  Buf = STRING(BASE + 4);
VAR
  s: Sub;
  a: Arr;
  b: Buf;
  i: INTEGER;
BEGIN
  WRITELN(ARITH, ' ', NEGMUL, ' ', WORDSUM, ' ', HI, ' ', LO, ' ', ABSV, ' ', SQRV);
  WRITELN(B1, ' ', B2, ' ', B3);
  WRITELN(GREET);
  WRITELN(PAIR);
  s := 15;
  a[9] := 42;
  b := '12345678901234';
  WRITELN(LOWER(s), ' ', UPPER(s), ' ', LOWER(a), ' ', UPPER(a), ' ', UPPER(b));
  FOR i := 10 TO 15 DO
  BEGIN
    CASE i OF
      BASE: WRITE('ten ');
      BASE + 1 .. BASE + 3: WRITE('mid ');
      BASE + 4: WRITE('fourteen ');
      OTHERWISE
        WRITE('other ')
    END;
  END;
  WRITELN;
  WRITELN('hi' * ' ' * 'there');
END.
