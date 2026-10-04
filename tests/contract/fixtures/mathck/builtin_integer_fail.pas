{$MATHCK+}
{ One trapping INTEGER builtin call per case; the case number arrives on
  stdin. A prints once, proving single evaluation of the argument before
  the trap. Every builtin name sits at column 18 on the line after its
  case label. Transcripts: builtin_integer_fail.expected. }
PROGRAM BuiltinFailure;
VAR g: INTEGER; k: INTEGER;
FUNCTION A: INTEGER; BEGIN WRITELN('arg'); A := g END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN g := 32767;
         WRITELN(SUCC(A)) END;
    1: BEGIN g := -32768;
         WRITELN(PRED(A)) END;
    2: BEGIN g := -32768;
         WRITELN(ABS(A)) END;
    3: BEGIN g := 182;
         WRITELN(SQR(A)) END;
    4: BEGIN g := -182;
         WRITELN(SQR(A)) END;
    5: BEGIN g := -32768;
         WRITELN(SQR(A)) END
  END;
  WRITELN('unreachable')
END.
