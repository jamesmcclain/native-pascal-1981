PROGRAM huge(n, k);
{ One 16 MiB frame, larger than the reduced stack the suite runs it under.
  The self-call (never taken: n is 0) keeps the routine out of main. }
{$INITCK-}{$MATHCK-}
VAR n, k: INTEGER;
FUNCTION big(m: INTEGER): INTEGER32;
VAR b: ARRAY [0..4194303] OF INTEGER32; i: INTEGER32;
BEGIN
  FOR i := 0 TO 4194303 DO b[i] := i;
  IF m > 0 THEN big := big(m - 1) + b[k] ELSE big := b[k];
END;
BEGIN
  WRITELN('start');
  WRITELN(big(n));
  WRITELN('done');
END.
