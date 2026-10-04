{ VECTOR [4] OF INTEGER64: lane failures, wraps and VSUM/VPROD folds.
  The case number arrives on stdin; each case prints prefix just
  before its operation. The suite prepends the MATHCK+ or MATHCK-
  directive. Transcripts: vector_integer64_checked.expected (MATHCK+) and
  vector_integer64_unchecked.expected (MATHCK-).
  64-bit lane values beyond 2^53 are built from 32-bit halves in the
  scalar t, because such literals lose precision. }
PROGRAM VectorCases;
TYPE V = VECTOR [4] OF INTEGER64;
VAR a, b, c: V; t, s: INTEGER64; k: INTEGER;
BEGIN
  READLN(k);
  CASE k OF
    0: BEGIN
      { Negation: lane 2 is the lowest lane whose negation does not fit; lane 3 fails too. }
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[0] := t;
      t := 0;
      a[1] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[2] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[3] := t;
      WRITELN('prefix');
      c := -a;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    1: BEGIN
      { +: lane 2 is the lowest overflowing lane and lane 3 overflows too, so MATHCK+ must name lane 2. }
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[0] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967294;
      a[1] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[2] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[3] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      b[0] := t;
      t := 1;
      b[1] := t;
      t := 1;
      b[2] := t;
      t := -1;
      b[3] := t;
      WRITELN('prefix');
      c := a + b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    2: BEGIN
      { -: lane 2 is the lowest overflowing lane and lane 3 overflows too, so MATHCK+ must name lane 2. }
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[0] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 1;
      a[1] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[2] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[3] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      b[0] := t;
      t := 1;
      b[1] := t;
      t := 1;
      b[2] := t;
      t := -1;
      b[3] := t;
      WRITELN('prefix');
      c := a - b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    3: BEGIN
      { *: lane 2 is the lowest overflowing lane and lane 3 overflows too, so MATHCK+ must name lane 2. }
      t := -1;
      a[0] := t;
      t := -1073741824;
      t := t * 4294967296;
      t := t + 0;
      a[1] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[2] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[3] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      b[0] := t;
      t := 2;
      b[1] := t;
      t := 2;
      b[2] := t;
      t := -1;
      b[3] := t;
      WRITELN('prefix');
      c := a * b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    4: BEGIN
      { DIV: lane 2 has a zero divisor (lane 3 too); this fails under either setting. }
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[0] := t;
      t := 7;
      a[1] := t;
      t := 9;
      a[2] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[3] := t;
      t := 1;
      b[0] := t;
      t := 2;
      b[1] := t;
      t := 0;
      b[2] := t;
      t := 0;
      b[3] := t;
      WRITELN('prefix');
      c := a DIV b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    5: BEGIN
      { MIN DIV -1 in lanes 1 and 2: DIV is MIN under MATHCK- and an overflow under MATHCK+; MOD is 0 under both. }
      t := 7;
      a[0] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[1] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[2] := t;
      t := 1;
      a[3] := t;
      t := 2;
      b[0] := t;
      t := -1;
      b[1] := t;
      t := -1;
      b[2] := t;
      t := 1;
      b[3] := t;
      WRITELN('prefix');
      c := a DIV b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    6: BEGIN
      { MOD: lane 2 has a zero divisor (lane 3 too); this fails under either setting. }
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[0] := t;
      t := 7;
      a[1] := t;
      t := 9;
      a[2] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[3] := t;
      t := 1;
      b[0] := t;
      t := 2;
      b[1] := t;
      t := 0;
      b[2] := t;
      t := 0;
      b[3] := t;
      WRITELN('prefix');
      c := a MOD b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    7: BEGIN
      { MIN MOD -1 in lanes 1 and 2 is 0 under either setting. }
      t := 7;
      a[0] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[1] := t;
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[2] := t;
      t := 1;
      a[3] := t;
      t := 2;
      b[0] := t;
      t := -1;
      b[1] := t;
      t := -1;
      b[2] := t;
      t := 1;
      b[3] := t;
      WRITELN('prefix');
      c := a MOD b;
      WRITELN(c[0]);
      WRITELN(c[1]);
      WRITELN(c[2]);
      WRITELN(c[3])
    END;
    8: BEGIN
      { VSUM: the first line prints a fold that fits; the second fold fails at its first step past the range (left = partial result), and wraps under MATHCK-. }
      t := -2147483648;
      t := t * 4294967296;
      t := t + 0;
      a[0] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[1] := t;
      t := -1;
      a[2] := t;
      t := 1;
      a[3] := t;
      WRITELN(VSUM(a));
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967294;
      a[0] := t;
      t := 1;
      a[1] := t;
      t := 1;
      a[2] := t;
      t := 0;
      a[3] := t;
      WRITELN('prefix');
      s := VSUM(a); WRITELN(s)
    END;
    9: BEGIN
      { VPROD: the first line prints a fold that fits; the second fold fails at its first step past the range (left = partial result), and wraps under MATHCK-. }
      t := -1;
      a[0] := t;
      t := 2147483647;
      t := t * 4294967296;
      t := t + 4294967295;
      a[1] := t;
      t := 1;
      a[2] := t;
      t := -1;
      a[3] := t;
      WRITELN(VPROD(a));
      t := 1073741824;
      t := t * 4294967296;
      t := t + 0;
      a[0] := t;
      t := 1;
      a[1] := t;
      t := 2;
      a[2] := t;
      t := 0;
      a[3] := t;
      WRITELN('prefix');
      s := VPROD(a); WRITELN(s)
    END
  END
END.
