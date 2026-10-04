{$MATHCK+}
{ The first overflowing INTEGER8 op INTEGER row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_integer8_integer_fail.expected. }
PROGRAM MixedWidthFailure;
VAR gl: INTEGER8; gr: INTEGER; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := -128; gr := -32768;
         WRITELN(gl + gr) END;
    1: BEGIN gl := -128; gr := 32767;
         WRITELN(gl - gr) END;
    2: BEGIN gl := -128; gr := -32768;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
