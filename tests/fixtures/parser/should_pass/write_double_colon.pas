(* P::N WRITE data-parameter form (manual 12-17; discrepancy D-002).
   Width omitted -> default field width; N gives fixed-point precision.
   Vintage 1981 compiler accepts; output for 123.456::2 is '        123.46'. *)
PROGRAM T002;
VAR x: REAL;
BEGIN
  x := 123.456;
  WRITELN(x::2)
END.
