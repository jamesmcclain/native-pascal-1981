{$MATHCK+}
{ The first overflowing WORD64 op WORD8 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_word64_word8_fail.expected.
  INTEGER64 and WORD64 values beyond 2^53 are built from 32-bit halves,
  because such literals lose precision (a separately recorded gap). }
PROGRAM MixedWidthFailure;
VAR gl: WORD64; gr: WORD8; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 4294967295; gl := gl * 4294967296; gl := gl + 4294967295; gr := 1;
         WRITELN(gl + gr) END;
    1: BEGIN gl := 0; gr := 1;
         WRITELN(gl - gr) END;
    2: BEGIN gl := 2147483648; gl := gl * 4294967296; gl := gl + 0; gr := 2;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
