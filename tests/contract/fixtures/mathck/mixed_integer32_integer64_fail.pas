{$MATHCK+}
{ The first overflowing INTEGER32 op INTEGER64 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_integer32_integer64_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidthFailure;
VAR gl: INTEGER32; gr: INTEGER64; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := -2147483648; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0;
         WRITELN(gl + gr) END;
    1: BEGIN gl := -2147483648; gr := 2147483647; gr := gr * 4294967296; gr := gr + 4294967295;
         WRITELN(gl - gr) END;
    2: BEGIN gl := -2147483648; gr := -2147483648; gr := gr * 4294967296; gr := gr + 0;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
