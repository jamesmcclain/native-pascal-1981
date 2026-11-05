{ DIALECT: vintage extended }
PROGRAM write_string_funcs(OUTPUT);
{ WRITE of an LSTRING- or STRING(n)-valued function call, niladic and with
  parameters, plain and with a field width. Each call runs exactly once. }
TYPE Fixed = STRING(4); Str255 = LSTRING(255);
VAR calls: INTEGER;
FUNCTION F: LSTRING(20);
BEGIN calls := calls + 1; F := 'hello' END;
FUNCTION G(n: INTEGER): LSTRING(20);
VAR s: LSTRING(20);
BEGIN
  calls := calls + 1; s := 'ggggg'; s[0] := CHR(n);
  G := s
END;
FUNCTION H(c: CHAR): Fixed;
VAR r: Fixed;
BEGIN calls := calls + 1; r := 'ab..'; r[3] := c; H := r END;
FUNCTION Greet(who: Str255): Str255;
VAR r: Str255;
BEGIN calls := calls + 1; r := 'hi, '; CONCAT(r, who); Greet := r END;
BEGIN
  calls := 0;
  WRITELN(F); WRITELN(F:8, '|');
  WRITELN('[', G(3), ']', G(2):5, '|');
  WRITELN(H('x')); WRITELN(H('y'):6, '|');
  WRITE(F, ' ', G(1)); WRITELN;
  WRITELN(Greet('bob'), '|', Greet(F):10, '|');
  WRITELN('calls=', calls:1)
END.
