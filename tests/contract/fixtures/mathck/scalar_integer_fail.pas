{$MATHCK+}
{ One trapping INTEGER operation per case; the case number arrives on
  stdin. L and R print once each, proving single left-to-right evaluation
  before the trap. Every operator sits at column 20 (unary minus at 18) on
  the line after its case label. Transcripts: scalar_integer_fail.expected. }
PROGRAM OverflowFailure;
VAR gl, gr: INTEGER; k: INTEGER;
FUNCTION L: INTEGER; BEGIN WRITELN('left'); L := gl END;
FUNCTION R: INTEGER; BEGIN WRITELN('right'); R := gr END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 32767; gr := 1;
         WRITELN(L + R) END;
    1: BEGIN gl := -32768; gr := -1;
         WRITELN(L + R) END;
    2: BEGIN gl := -32768; gr := 1;
         WRITELN(L - R) END;
    3: BEGIN gl := 32767; gr := -1;
         WRITELN(L - R) END;
    4: BEGIN gl := 32767; gr := 2;
         WRITELN(L * R) END;
    5: BEGIN gl := -32768; gr := -1;
         WRITELN(L * R) END;
    6: BEGIN gl := -32768; gr := -1;
         WRITELN(L DIV R) END;
    7: BEGIN gl := -32768;
         WRITELN(- L) END
  END;
  WRITELN('unreachable')
END.
