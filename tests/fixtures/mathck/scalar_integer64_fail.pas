{$MATHCK+}
{ One trapping INTEGER64 operation per case; the case number arrives on
  stdin. L and R print once each, proving single left-to-right evaluation
  before the trap. Every operator sits at column 20 (unary minus at 18) on
  the line after its case label. Transcripts: scalar_integer64_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM OverflowFailure;
VAR gl, gr: INTEGER64; k: INTEGER;
FUNCTION L: INTEGER64; BEGIN WRITELN('left'); L := gl END;
FUNCTION R: INTEGER64; BEGIN WRITELN('right'); R := gr END;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1;
         WRITELN(L + R) END;
    1: BEGIN gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1;
         WRITELN(L + R) END;
    2: BEGIN gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 1;
         WRITELN(L - R) END;
    3: BEGIN gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := -1;
         WRITELN(L - R) END;
    4: BEGIN gl := 2147483647; gl := gl * 4294967296; gl := gl + 4294967295; gr := 2;
         WRITELN(L * R) END;
    5: BEGIN gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1;
         WRITELN(L * R) END;
    6: BEGIN gl := -2147483648; gl := gl * 4294967296; gl := gl + 0; gr := -1;
         WRITELN(L DIV R) END;
    7: BEGIN gl := -2147483648; gl := gl * 4294967296; gl := gl + 0;
         WRITELN(- L) END
  END;
  WRITELN('unreachable')
END.
