{ MATHCK on/off twin: tests/mathck_scalar.sh prepends $MATHCK+ or $MATHCK-
  and requires identical output (twin_arith.out). No operation overflows. }
PROGRAM TwinArith(output);
CONST
  Limit = 32767;
  Low = -32768;
TYPE
  Pair = RECORD x, y: INTEGER END;
VAR
  i, j, k, f, m1: INTEGER;
  w, sum: WORD;
  p: Pair;
  cells: ARRAY [1..10] OF INTEGER;

FUNCTION Gcd(a, b: INTEGER): INTEGER;
BEGIN
  IF b = 0 THEN Gcd := a ELSE Gcd := Gcd(b, a MOD b)
END;

FUNCTION Fib(n: INTEGER): INTEGER;
VAR a, b, t, m: INTEGER;
BEGIN
  a := 0; b := 1;
  FOR m := 1 TO n DO BEGIN t := a + b; a := b; b := t END;
  Fib := a
END;

BEGIN
  f := 1;
  FOR i := 1 TO 7 DO f := f * i;
  WRITELN('fact7 ', f);
  WRITELN('fib22 ', Fib(22));
  WRITELN('gcd ', Gcd(32767, 4681), ' ', Gcd(-12, 18));
  WRITELN('limits ', Limit, ' ', Low, ' ', -Limit, ' ', Low + Limit);
  k := Low + 1; k := k - 1; m1 := -1;
  WRITELN('min ', k, ' ', k DIV 2, ' ', k MOD 7, ' ', k MOD m1, ' ', k DIV 1);
  j := -16384; WRITELN('double ', j * 2, ' ', -(j * 2 + 1));
  sum := 0;
  FOR i := 1 TO 10 DO
  BEGIN
    cells[i] := i * i - 3 * i;
    sum := sum + WRD(i) * 1000
  END;
  k := 0;
  FOR i := 1 TO 10 DO k := k + cells[11 - i] * (i MOD 3 - 1);
  WRITELN('cells ', cells[1], ' ', cells[10], ' ', k, ' ', sum);
  w := 65535; w := w - 1; w := w DIV 3 * 3 + 1;
  WRITELN('word ', w, ' ', w MOD 1000, ' ', -WRD(0));
  p.x := 181; p.y := -181;
  WRITELN('pair ', p.x * p.x, ' ', p.x * p.y, ' ', -p.y - p.x);
  i := 7; j := -2;
  WRITELN('trunc ', i DIV j, ' ', i MOD j, ' ', -i DIV 2, ' ', -i MOD 2)
END.
