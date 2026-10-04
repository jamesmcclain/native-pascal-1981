{$MATHCK+}
{ The first overflowing WORD8 op WORD row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_word8_word_fail.expected. }
PROGRAM MixedWidthFailure;
VAR gl: WORD8; gr: WORD; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 1; gr := 65535;
         WRITELN(gl + gr) END;
    1: BEGIN gl := 0; gr := 1;
         WRITELN(gl - gr) END;
    2: BEGIN gl := 2; gr := 32768;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
