{$MATHCK+}
{ The first overflowing INTEGER32 op INTEGER8 row for each operator; the case
  number arrives on stdin. Each failure reports the operands at their
  own values and the operator at column 21 on the line after its case
  label. Transcripts: mixed_integer32_integer8_fail.expected. }
PROGRAM MixedWidthFailure;
VAR gl: INTEGER32; gr: INTEGER8; k: INTEGER;
BEGIN
  READLN(k);
  WRITELN('prefix');
  CASE k OF
    0: BEGIN gl := -2147483648; gr := -128;
         WRITELN(gl + gr) END;
    1: BEGIN gl := -2147483648; gr := 1;
         WRITELN(gl - gr) END;
    2: BEGIN gl := -2147483648; gr := -128;
         WRITELN(gl * gr) END;
    3: BEGIN gl := -2147483648; gr := -1;
         WRITELN(gl DIV gr) END
  END;
  WRITELN('unreachable')
END.
