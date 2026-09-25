{ DIALECT: extended }
PROGRAM indexck_int64_bad(OUTPUT);
VAR a: ARRAY[0..1] OF INTEGER; i: INTEGER64;
BEGIN
  i := -1;
  WRITELN(a[i]);
  WRITELN('unreachable')
END.
