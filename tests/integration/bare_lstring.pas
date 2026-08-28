{ LSTRING is a predeclared identifier, not a keyword, so a bare `LSTRING`
  parses as a plain NamedType with no param. It means LSTRING(256), the same
  default a bare STRING takes -- and the same thing the Python reference
  resolves it to. A user TYPE of that name still wins over the predeclared
  meaning (IBM Pascal, Aug 1981, p.3-7). }
PROGRAM BareLString(output);
VAR
  s: LSTRING;
BEGIN
  s := 'bare lstring';
  WRITELN(s);
END.
