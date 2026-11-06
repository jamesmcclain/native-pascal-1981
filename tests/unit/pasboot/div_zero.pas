{ A zero divisor is a run-time error, never C undefined behaviour or a
  SIGFPE: pasboot ignores MATHCK, but the native compiler reports a zero
  divisor under either setting, and so does pasboot's generated C. }
(*$INCLUDE:'testio.inc'*)
PROGRAM div_zero(input, output);
USES testio;
VAR w, z: INTEGER32;
BEGIN
  w := 7; z := 0;
  WriteLabel('before'); WRITELN;
  WriteInt(w DIV z); WRITELN;
  WriteLabel('after'); WRITELN;
END.
