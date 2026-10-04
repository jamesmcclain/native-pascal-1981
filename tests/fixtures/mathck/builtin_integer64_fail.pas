{$MATHCK+}
{ One trapping INTEGER64 builtin call per case; the case number arrives on
  stdin. A prints once, proving single evaluation of the argument before
  the trap. Every builtin name sits at column 18 on the line after its
  case label. Transcripts: builtin_integer64_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM BuiltinFailure;
VAR g: INTEGER64; k: INTEGER;
FUNCTION A: INTEGER64; BEGIN WRITELN('arg'); A := g END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN g := 2147483647; g := g * 4294967296; g := g + 4294967295;
         WRITELN(SUCC(A)) END;
    1: BEGIN g := -2147483648; g := g * 4294967296; g := g + 0;
         WRITELN(PRED(A)) END;
    2: BEGIN g := -2147483648; g := g * 4294967296; g := g + 0;
         WRITELN(ABS(A)) END;
    3: BEGIN g := 3037000500;
         WRITELN(SQR(A)) END;
    4: BEGIN g := -3037000500;
         WRITELN(SQR(A)) END;
    5: BEGIN g := -2147483648; g := g * 4294967296; g := g + 0;
         WRITELN(SQR(A)) END
  END;
  WRITELN('unreachable')
END.
