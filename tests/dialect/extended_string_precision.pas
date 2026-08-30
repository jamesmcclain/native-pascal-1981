{ DIALECT: extended }
PROGRAM ExtendedStringPrecision(output);
VAR
  fixed_text: STRING(8);
  varying_text: LSTRING(8);
BEGIN
  fixed_text := 'ABCDEFGH';
  varying_text := 'ABCDEFGH';
  WRITELN('|', 'ABCDEFG'::3, '|');
  WRITELN('|', 'ABCDEFG':10:3, '|');
  WRITELN('|', fixed_text::3, '|');
  WRITELN('|', fixed_text:10:3, '|');
  WRITELN('|', varying_text::3, '|');
  WRITELN('|', varying_text:10:3, '|');
  WRITELN('|', 12:5, '|');
  WRITELN('|', 1.25:8:2, '|')
END.
