{$MATHCK+}
PROGRAM fold(input, output);
{ tests/mathck_optimization.py: the checks on i + 1, i * 2 - 1 and -i have
  operands bounded by constant FOR limits, so LLVM folds them at O1-O3. The
  accumulations into k and the operations on n (read at run time) stay. }
VAR i, k, n, s: INTEGER;
BEGIN
  READLN(n);
  k := 0;
  FOR i := 1 TO 32766 DO k := k + (i + 1) MOD 2;
  FOR i := -16383 TO 16383 DO k := k + (i * 2 - 1) MOD 2;
  FOR i := -32767 TO 32767 DO k := k + (-i) MOD 2;
  s := n + 1;
  s := s * n;
  WRITELN(k, s)
END.
