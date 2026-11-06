{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-26: nested routines read and write their enclosing routines' locals
  and parameters (value and VAR) through static links: VAR passing, WITH,
  FOR, strings, pointers, three levels of nesting, recursion of the inner
  and of the outer routine, FORWARD siblings, and assignments to an
  enclosing FUNCTION's scalar, LSTRING and RECORD result. }
PROGRAM uplevel_access(OUTPUT);
TYPE
  Pair = RECORD a, b: INTEGER; END;
  Vec = ARRAY [1..5] OF INTEGER;
  PInt = ^INTEGER;
VAR
  g: INTEGER;
  gv: Vec;

PROCEDURE Bump(VAR n: INTEGER);
BEGIN
  n := n + 100;
END;

PROCEDURE Outer(p: INTEGER; VAR q: INTEGER);
VAR
  x: INTEGER;
  r: Pair;
  v: Vec;
  s: LSTRING(20);
  c: CHAR;
  ok: BOOLEAN;
  i: INTEGER;
  ptr: PInt;

  PROCEDURE Show;
  BEGIN
    WRITELN('x=', x, ' p=', p, ' q=', q, ' r=', r.a, ',', r.b, ' s=', s,
            ' c=', c, ' ok=', ok);
  END;

  PROCEDURE Mutate;
  VAR k: INTEGER;
  BEGIN
    x := x + 1;
    p := p * 2;
    q := q - 1;
    r.a := r.a + 10;
    WITH r DO b := a + 1;
    FOR k := 1 TO 5 DO v[k] := k * x;
    s := 'changed';
    c := 'Z';
    ok := NOT ok;
    Bump(x);
    ptr^ := ptr^ + 1;
  END;

  FUNCTION SumV: INTEGER;
  VAR k, t: INTEGER;
  BEGIN
    t := 0;
    FOR k := 1 TO 5 DO t := t + v[k];
    SumV := t;
  END;

  PROCEDURE Level2;
  VAR y: INTEGER;
    PROCEDURE Level3;
      PROCEDURE Level4;
      BEGIN
        x := x + y;
        y := y + 1;
        Show;
      END;
    BEGIN
      Level4;
      Mutate;
    END;
  BEGIN
    y := 1000;
    Level3;
    WRITELN('y=', y);
  END;

BEGIN
  x := 1;
  r.a := 2;
  r.b := 3;
  FOR i := 1 TO 5 DO v[i] := 0;
  s := 'start';
  c := 'A';
  ok := TRUE;
  NEW(ptr);
  ptr^ := 41;
  Show;
  Mutate;
  Show;
  WRITELN('sum=', SumV, ' ptr=', ptr^);
  Level2;
  Show;
  DISPOSE(ptr);
END;

FUNCTION Fact(n: INTEGER): INTEGER;
VAR acc: INTEGER;
  PROCEDURE Step(k: INTEGER);
  BEGIN
    IF k > 1 THEN
    BEGIN
      acc := acc * k;
      Step(k - 1);
    END
    ELSE Fact := acc;
  END;
BEGIN
  acc := 1;
  Step(n);
END;

FUNCTION Fib(n: INTEGER): INTEGER;
{ Recursion of the outer routine: every activation has its own n. }
  FUNCTION Inner: INTEGER;
  BEGIN
    IF n < 2 THEN Inner := n
    ELSE Inner := Fib(n - 1) + Fib(n - 2);
  END;
BEGIN
  Fib := Inner;
END;

FUNCTION Sign(n: INTEGER): LSTRING(20);
  PROCEDURE SetIt;
  BEGIN
    IF n > 0 THEN Sign := 'positive' ELSE Sign := 'other';
  END;
BEGIN
  SetIt;
END;

FUNCTION MakePair(n: INTEGER): Pair;
  PROCEDURE Fill;
  BEGIN
    MakePair.a := n;
    MakePair.b := n * n;
  END;
BEGIN
  Fill;
END;

PROCEDURE Siblings;
VAR count: INTEGER;
  PROCEDURE B; FORWARD;
  PROCEDURE A(k: INTEGER);
  BEGIN
    count := count + 1;
    IF k > 0 THEN B;
  END;
  PROCEDURE B;
  BEGIN
    count := count + 10;
    A(0);
  END;
BEGIN
  count := 0;
  A(1);
  WRITELN('count=', count);
END;

VAR
  z: INTEGER;
  mp: Pair;
BEGIN
  g := 0;
  z := 5;
  Outer(3, z);
  WRITELN('z=', z);
  WRITELN('fact=', Fact(6));
  WRITELN('fib=', Fib(10));
  WRITELN(Sign(3), ' ', Sign(-1));
  mp := MakePair(7);
  WRITELN('pair=', mp.a, ',', mp.b);
  Siblings;
END.
