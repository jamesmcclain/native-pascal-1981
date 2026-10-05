{$MATHCK+}
{ One trapping WORD64 operation per case; the case number arrives on
  stdin. L and R print once each, proving single left-to-right evaluation
  before the trap. Every operator sits at column 20 (unary minus at 18) on
  the line after its case label. Transcripts: scalar_word64_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM OverflowFailure;
VAR gl, gr: WORD64; k: INTEGER;
FUNCTION L: WORD64; BEGIN WRITELN('left'); L := gl END;
FUNCTION R: WORD64; BEGIN WRITELN('right'); R := gr END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1;
         WRITELN(L + R) END;
    1: BEGIN gl := 0; gr := 1;
         WRITELN(L - R) END;
    2: BEGIN gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2;
         WRITELN(L * R) END;
    3: BEGIN gl := 1;
         WRITELN(- L) END;
    4: BEGIN gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295;
         WRITELN(- L) END
  END;
  WRITELN('unreachable')
END.
