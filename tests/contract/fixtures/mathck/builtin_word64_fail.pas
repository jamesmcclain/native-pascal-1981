{$MATHCK+}
{ One trapping WORD64 builtin call per case; the case number arrives on
  stdin. A prints once, proving single evaluation of the argument before
  the trap. Every builtin name sits at column 18 on the line after its
  case label. Transcripts: builtin_word64_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM BuiltinFailure;
VAR g: WORD64; k: INTEGER;
FUNCTION A: WORD64; BEGIN WRITELN('arg'); A := g END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN g := 4294967295; g := g * 4294967296; g := g + 4294967295;
         WRITELN(SUCC(A)) END;
    1: BEGIN g := 0;
         WRITELN(PRED(A)) END;
    2: BEGIN g := 4294967296;
         WRITELN(SQR(A)) END;
    3: BEGIN g := 4294967295; g := g * 4294967296; g := g + 4294967295;
         WRITELN(SQR(A)) END
  END;
  WRITELN('unreachable')
END.
