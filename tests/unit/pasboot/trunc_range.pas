{ TRUNC of a value outside INTEGER64 is a run-time error, not an undefined
  C conversion. }
(*$INCLUDE:'testio.inc'*)
PROGRAM trunc_range(input, output);
USES testio;
VAR r: REAL;
BEGIN
  r := 2.5;
  WriteInt(TRUNC(r)); WRITELN;
  r := 1.0E30;
  WriteInt(TRUNC(r)); WRITELN;
END.
