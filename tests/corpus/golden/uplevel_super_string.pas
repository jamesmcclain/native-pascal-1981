{ DIALECT: vintage extended }
{ OPT: 0 2 }
{ NEW-26 with NEW-29: a nested routine uses an enclosing routine's
  conformant STRING and LSTRING formals. The captured formal keeps its
  caller's UPPER (found through the static link), one and two levels
  down, and can be read, indexed, written through VAR, and forwarded to
  another conformant formal. }
PROGRAM uplevel_super_string(OUTPUT);
VAR
  s5: STRING(5);
  s3: STRING(3);
  l9: LSTRING(9);

PROCEDURE Echo(CONST t: STRING);
BEGIN
  WRITELN('echo ', UPPER(t), ' ', t);
END;

PROCEDURE Show(CONST s: STRING; VAR l: LSTRING);
  PROCEDURE Inner;
    PROCEDURE Deeper;
    BEGIN
      WRITELN('deeper ', UPPER(s), ' ', s[UPPER(s)], ' ', UPPER(l));
      l[1] := 'Z';
    END;
  BEGIN
    WRITELN('inner ', UPPER(s), ' ', s, ' ', UPPER(l), ' ', ORD(l.LEN), ' ', l);
    Deeper;
    Echo(s);
    COPYLST('nest', l);
  END;
BEGIN
  Inner;
  WRITELN('show ', l);
END;

BEGIN
  s5 := 'abcde';
  s3 := 'xyz';
  COPYLST('hello', l9);
  Show(s5, l9);
  WRITELN('main ', l9);
  Show(s3, l9);
  WRITELN('main ', l9);
END.
