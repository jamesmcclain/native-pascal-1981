{ A RANGECK subrange store failing in the primary file after an include is
  located without a file name. }
PROGRAM runtime_subrange_primary(OUTPUT);
TYPE Digit = 0..9;
VAR d: Digit; i: INTEGER;
(*$INCLUDE:'runtime_subrange.inc'*)
BEGIN
  WRITELN('start');
  Store(9);
  i := -1;
  d := i
END.
