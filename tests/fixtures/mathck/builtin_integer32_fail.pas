{$MATHCK+}
{ One trapping INTEGER32 builtin call per case; the case number arrives on
  stdin. A prints once, proving single evaluation of the argument before
  the trap. Every builtin name sits at column 18 on the line after its
  case label. Transcripts: builtin_integer32_fail.expected. }
PROGRAM BuiltinFailure;
VAR g: INTEGER32; k: INTEGER;
FUNCTION A: INTEGER32; BEGIN WRITELN('arg'); A := g END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN g := 2147483647;
         WRITELN(SUCC(A)) END;
    1: BEGIN g := -2147483648;
         WRITELN(PRED(A)) END;
    2: BEGIN g := -2147483648;
         WRITELN(ABS(A)) END;
    3: BEGIN g := 46341;
         WRITELN(SQR(A)) END;
    4: BEGIN g := -46341;
         WRITELN(SQR(A)) END;
    5: BEGIN g := -2147483648;
         WRITELN(SQR(A)) END
  END;
  WRITELN('unreachable')
END.
