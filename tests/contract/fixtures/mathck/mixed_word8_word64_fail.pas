{$MATHCK+}
{ The first overflowing WORD8 op WORD64 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_word8_word64_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidthFailure;
VAR gl: WORD8; gr: WORD64; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 1; gr := 4294967295; gr := gr * 4294967296; gr := gr + 4294967295;
         WRITELN(gl + gr) END;
    1: BEGIN gl := 0; gr := 1;
         WRITELN(gl - gr) END;
    2: BEGIN gl := 2; gr := 2147483648; gr := gr * 4294967296; gr := gr + 0;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
