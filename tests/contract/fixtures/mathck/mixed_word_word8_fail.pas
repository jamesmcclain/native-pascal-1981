{$MATHCK+}
{ The first overflowing WORD op WORD8 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_word_word8_fail.expected. }
PROGRAM MixedWidthFailure;
VAR gl: WORD; gr: WORD8; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := 65535; gr := 1;
         WRITELN(gl + gr) END;
    1: BEGIN gl := 0; gr := 1;
         WRITELN(gl - gr) END;
    2: BEGIN gl := 32768; gr := 2;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
