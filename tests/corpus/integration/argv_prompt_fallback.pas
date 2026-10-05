PROGRAM prompted(n, c);
{ No command-line arguments at all: every heading parameter falls back to the
  keyboard, each read preceded by the documented '<name>: ' prompt on stdout
  (manual 13-5..13-7). The .stdin file stands in for the keyboard. }
VAR
  n: INTEGER;
  c: CHAR;
BEGIN
  WRITELN('n=', n);
  WRITELN('c=', c);
END.
