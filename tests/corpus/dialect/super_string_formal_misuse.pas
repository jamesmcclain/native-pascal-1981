{ DIALECT: vintage extended }
{ NEW-29: what a conformant STRING/LSTRING formal does not allow is a
  located type error, never a codegen abort. Such a formal is not assigned
  or (a STRING) compared as a whole, has no SIZEOF, and is passed only to
  another conformant formal, a CONST formal never as VAR. A VAR actual is
  a variable; an LSTRING formal takes no STRING(n), CHAR variable or
  STRING formal; a CONST actual is no expression with operators; an
  actual of capacity above 32767 has no INTEGER UPPER (IBM manual 6-15
  to 6-19, 6-38, 10-9 and 10-10). }
PROGRAM SuperStringFormalMisuse(OUTPUT);
VAR
  a: STRING(5);
  l: LSTRING(10);
  c: CHAR;
  big: STRING(40000);
  bigl: LSTRING(40000);
  i: INTEGER;

PROCEDURE PS(VAR s: STRING); BEGIN END;
PROCEDURE PL(VAR s: LSTRING); BEGIN END;
PROCEDURE CS(CONST s: STRING); BEGIN END;
PROCEDURE CL(CONST s: LSTRING); BEGIN END;
PROCEDURE Fixed(VAR s: LSTRING(10)); BEGIN END;
PROCEDURE ValS(s: LSTRING(10)); BEGIN END;

PROCEDURE Body(VAR s: STRING; CONST t: STRING; VAR u: LSTRING);
BEGIN
  s := a;
  a := s;
  u := 'abc';
  IF s = t THEN WRITELN;
  Fixed(u);
  ValS(u);
  PS(t);
  PL(s);
  i := SIZEOF(s);
END;

BEGIN
  PS('abc');
  PL(a);
  CL(a);
  CL(c);
  PS(i);
  CS(big);
  PL(bigl);
  CS(c = c);
END.
