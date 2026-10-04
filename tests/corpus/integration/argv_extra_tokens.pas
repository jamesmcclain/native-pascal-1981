PROGRAM extra(n);
{ More command-line tokens than heading parameters: the surplus tokens are
  simply never consumed and must not disturb the bound value. }
VAR
  n: INTEGER;
BEGIN
  WRITELN('n=', n);
END.
