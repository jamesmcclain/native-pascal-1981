{ DIALECT: vintage extended }
{ NEW-47: what a ^STRING / ^LSTRING super-array pointer referent does not
  allow is a located type error, never a codegen abort: whole assignment to
  or from p^, whole comparison of ^STRING, passing p^ to a non-conformant
  formal, or passing ^STRING to an LSTRING formal (IBM manual 6-15..6-19). }
PROGRAM SuperStringPointerMisuse(OUTPUT);
VAR
  p: ^LSTRING;
  s, t: ^STRING;
  l: LSTRING(10);
  a: STRING(5);

PROCEDURE PL(VAR x: LSTRING); BEGIN END;
PROCEDURE CL(CONST x: LSTRING); BEGIN END;
PROCEDURE Fixed(VAR x: LSTRING(10)); BEGIN END;
PROCEDURE ValS(x: LSTRING(10)); BEGIN END;

BEGIN
  p^ := 'abc';
  s^ := 'abcde';
  l := p^;
  a := s^;
  IF s^ = t^ THEN WRITELN;
  Fixed(p^);
  ValS(p^);
  PL(s^);
  CL(s^);
END.
