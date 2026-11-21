{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-47: $INDEXCK guards subscripts of ^STRING and ^LSTRING super-array
  referents against their declared lower (1 or 0) and runtime UPPER(p^). }
PROGRAM SuperStringPointerIndexckBad(OUTPUT);
VAR
  s: ^STRING;
  k: INTEGER;
BEGIN
  NEW(s, 3);
  s^[1] := 'a';
  s^[2] := 'b';
  s^[3] := 'c';
  WRITELN(s^, ' ', UPPER(s^));
  k := 4;
  s^[k] := 'z';
  WRITELN('not reached');
  DISPOSE(s);
END.
