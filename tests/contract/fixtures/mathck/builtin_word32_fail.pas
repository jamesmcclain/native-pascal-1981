{$MATHCK+}
{ One trapping WORD32 builtin call per case; the case number arrives on
  stdin. A prints once, proving single evaluation of the argument before
  the trap. Every builtin name sits at column 18 on the line after its
  case label. Transcripts: builtin_word32_fail.expected. }
PROGRAM BuiltinFailure;
VAR g: WORD32; k: INTEGER;
FUNCTION A: WORD32; BEGIN WRITELN('arg'); A := g END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN g := 4294967295;
         WRITELN(SUCC(A)) END;
    1: BEGIN g := 0;
         WRITELN(PRED(A)) END;
    2: BEGIN g := 65536;
         WRITELN(SQR(A)) END;
    3: BEGIN g := 4294967295;
         WRITELN(SQR(A)) END
  END;
  WRITELN('unreachable')
END.
