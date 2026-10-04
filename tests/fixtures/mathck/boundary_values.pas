{ MATHCK boundary values (tests/mathck_boundary_values.sh): every operation
  below has a representable result -- most land exactly on 32767, -32768, 0
  or 65535 -- so none may trap under MATHCK+. Operands come from variables,
  so each operation is checked at run time; the `consts' line repeats the
  listed values as fully constant (folded) expressions. A sign applies to
  the whole term, so the literal `-16384 * 2' means -(16384 * 2), whose
  16384 * 2 does not fit INTEGER; the folded form is written (-16384) * 2. -32768 is ordinary data, never a sentinel. }
PROGRAM BoundaryValues(output);
CONST
  CMax = 32767; CMin = -32768; CWMax = 65535;
VAR
  max, min, one, m1, two, seven, zero, h, i: INTEGER;
  wmax, w, wone: WORD;
BEGIN
  max := 32767; min := -32768; one := 1; m1 := -1; two := 2; seven := 7;
  zero := 0; h := -16384; wmax := 65535; wone := 1;
  WRITELN('literals ', max, ' ', min, ' ', zero, ' ', wmax);
  WRITELN('min results ', -max - one, ' ', h * two, ' ', PRED(-max),
          ' ', -max + m1, ' ', min + zero, ' ', min * one, ' ', min DIV one);
  WRITELN('max results ', max + zero, ' ', max * one, ' ', -(min + one),
          ' ', SUCC(max - one), ' ', ABS(min + one), ' ', max DIV one);
  WRITELN('zero results ', max - max, ' ', min - min, ' ', min + max + one,
          ' ', zero * min, ' ', -zero, ' ', ABS(zero), ' ', SQR(zero));
  WRITELN('div ', min MOD m1, ' ', -seven DIV two, ' ', -seven MOD two,
          ' ', seven DIV (-two), ' ', min DIV two, ' ', min MOD seven,
          ' ', max MOD min, ' ', min DIV max);
  w := wmax - wone; w := w + wone;
  WRITELN('word ', w, ' ', WRD(255) * WRD(257), ' ', SUCC(wmax - wone),
          ' ', wmax DIV wone, ' ', wmax MOD wmax, ' ', wmax - wmax,
          ' ', SQR(WRD(255)), ' ', PRED(wone));
  WRITELN('consts ', CMax, ' ', CMin, ' ', CWMax, ' ', -32767 - 1, ' ',
          (-16384) * 2, ' ', PRED(-32767), ' ', -32767 + (-1), ' ', -7 DIV 2,
          ' ', CMin MOD (-1), ' ', CMin DIV 1, ' ', 65534 + 1);
  i := min; i := PRED(i + one); WRITELN('chain ', i, ' ', i = min)
END.
