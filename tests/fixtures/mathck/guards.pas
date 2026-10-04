{$MATHCK+}
{ O0 guard order for tests/mathck_overflow.sh; the suite replaces {TYPE}
  with every scalar integer type. }
PROGRAM Guards;
VAR a, b, k: {TYPE};
BEGIN
a := 3; b := 2;
k := a + b; k := a - b; k := a * b;
k := a DIV b; k := -a; WRITELN(k)
END.
