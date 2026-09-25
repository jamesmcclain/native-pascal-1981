PROGRAM indexck_const_bad_load(OUTPUT);
VAR a: ARRAY[2..4] OF INTEGER;
BEGIN
  WRITELN(a[1]) { valid INTEGER constant, outside the declared bounds }
END.
