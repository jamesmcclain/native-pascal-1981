PROGRAM indexck_const_bad_store(OUTPUT);
CONST beyond = 5;
VAR a: ARRAY[2..4] OF INTEGER;
BEGIN
  WRITELN('before'); { must be flushed before the index diagnostic }
  a[beyond] := 42 { named constant, checked on store }
END.
