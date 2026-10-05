{$MATHCK+}
{ The first overflowing INTEGER op INTEGER32 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_integer_integer32_fail.expected. }
PROGRAM MixedWidthFailure;
VAR gl: INTEGER; gr: INTEGER32; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := -32768; gr := -2147483648;
         WRITELN(gl + gr) END;
    1: BEGIN gl := -32768; gr := 2147483647;
         WRITELN(gl - gr) END;
    2: BEGIN gl := -32768; gr := -2147483648;
         WRITELN(gl * gr) END
  END;
  WRITELN('unreachable')
END.
