{$MATHCK+}
{ The first overflowing INTEGER8 op INTEGER32 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_integer8_integer32_fail.expected. }
PROGRAM MixedWidthFailure;
VAR gl: INTEGER8; gr: INTEGER32; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := -128; gr := -2147483648;
         WRITELN(gl + gr) END;
    1: BEGIN gl := -128; gr := 2147483647;
         WRITELN(gl - gr) END;
    2: BEGIN gl := -128; gr := -2147483648;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
