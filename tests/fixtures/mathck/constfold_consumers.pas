{ Constant consumers are rebuilt from the exact truncating fold, not from
  an already truncated 16-bit operand: N DIV 2 = -65537 DIV 2 = -32768 (an
  assignment and an array index at the low bound), (-7) DIV 2 = -3 and
  100000 + ((-7) MOD 2) = 100000 + -1 = 99999 (G22) in an INTEGER32. }
PROGRAM Consumers;
CONST N = -65537;
TYPE Edge = ARRAY [-32768..-32767] OF INTEGER;
VAR a: Edge; k: INTEGER; wide: INTEGER32;
BEGIN
  k := N DIV 2; WRITELN(k);
  a[N DIV 2] := 42; WRITELN(a[-32768]);
  wide := (-7) DIV 2; WRITELN(wide);
  wide := 100000 + ((-7) MOD 2); WRITELN(wide)
END.
