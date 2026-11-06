PROGRAM recurse(depth, k);
{ Recursion with a 96 KiB frame. The array is filled and read at an index
  known only at run time, so no optimization level can drop the frame. }
{$INITCK-}{$MATHCK-}
VAR depth, k: INTEGER;
FUNCTION f(n: INTEGER): INTEGER;
VAR a: ARRAY [0..32767] OF INTEGER; i: INTEGER;
BEGIN
  FOR i := 0 TO 32767 DO a[i] := i + n;
  IF n > 0 THEN f := f(n - 1) + a[k] ELSE f := a[k];
END;
BEGIN
  WRITELN('start');
  WRITELN(f(depth));
  WRITELN('done');
END.
