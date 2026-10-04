{$MATHCK+}
{ One trapping INTEGER8 builtin call per case; the case number arrives on
  stdin. A prints once, proving single evaluation of the argument before
  the trap. Every builtin name sits at column 18 on the line after its
  case label. Transcripts: builtin_integer8_fail.expected. }
PROGRAM BuiltinFailure;
VAR g: INTEGER8; k: INTEGER;
FUNCTION A: INTEGER8; BEGIN WRITELN('arg'); A := g END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN g := 127;
         WRITELN(SUCC(A)) END;
    1: BEGIN g := -128;
         WRITELN(PRED(A)) END;
    2: BEGIN g := -128;
         WRITELN(ABS(A)) END;
    3: BEGIN g := 12;
         WRITELN(SQR(A)) END;
    4: BEGIN g := -12;
         WRITELN(SQR(A)) END;
    5: BEGIN g := -128;
         WRITELN(SQR(A)) END
  END;
  WRITELN('unreachable')
END.
