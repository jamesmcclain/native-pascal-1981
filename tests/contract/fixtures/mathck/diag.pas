{ One failing statement per case; the case number arrives on stdin.
  Cases 0-6 are the MATHCK classes: signed and unsigned overflow in a
  binary operator (0, 1), unary minus (2), SUCC (3), VSUM (4), and
  signed and unsigned division by zero (5, 6). Cases 7-10 are the
  neighbouring checks: a RANGECK store (7), a SUCC domain (8), an
  INDEXCK bound (9) and TRUNC (10). The suite prepends the MATHCK+ or
  MATHCK- directive. Transcripts: diag_checked.expected (MATHCK+, all
  cases) and diag_unchecked.expected (MATHCK-, cases 0-6: zero divisors
  still fail, overflow wraps and the program prints after). Each
  location is the line and column of the operator or function name. }
PROGRAM Diag(output);
TYPE Colour = (red, green, blue);
  V = VECTOR [4] OF INTEGER;
VAR n, i, k: INTEGER; w, z: WORD; s: 0..3; c: Colour; r: REAL;
  a: ARRAY [1..3] OF INTEGER; u: V; t: INTEGER;
BEGIN
  i := 32767; k := 0; w := 65535; z := 0; c := blue; r := 1.0E9;
  u := VSPLAT(20000, V); t := 0;
  READLN(n);
  WRITELN('prefix');
  CASE n OF
    0: BEGIN k := i + 1 END;
    1: BEGIN w := w * 2 END;
    2: BEGIN i := -32768; k := -i END;
    3: BEGIN k := SUCC(i) END;
    4: BEGIN t := VSUM(u) END;
    5: BEGIN k := i DIV k END;
    6: BEGIN w := w MOD z END;
    7: BEGIN k := 5; s := k END;
    8: BEGIN c := SUCC(c) END;
    9: BEGIN k := 4; a[k] := 1 END;
    10: BEGIN k := TRUNC(r) END
  END;
  WRITELN('after')
END.
