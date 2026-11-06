{ DIALECT: vintage extended }
{ OPT: 0 2 }
{$INITCK+}
{ NEW-29: strings carry no INITCK state, so a tracked CHAR seen through a
  conformant STRING formal is a modeled boundary: a VAR binding releases
  it (the callee may write it) and a CONST binding reads it at the call.
  Neither makes the CHAR an escaped local. }
PROGRAM SuperStringInitck(OUTPUT);

PROCEDURE SetFirst(VAR s: STRING);
BEGIN
  s[1] := 'k';
END;

PROCEDURE Show(CONST s: STRING);
BEGIN
  WRITELN('bound with upper ', UPPER(s));
END;

PROCEDURE Run;
VAR
  c, d: CHAR;
  a: ARRAY [1..2] OF CHAR;
BEGIN
  SetFirst(c);
  d := c;
  WRITELN('written through VAR: ', d);
  Show(c);
  a[1] := 'e';
  Show(a[1]);
  SetFirst(a[2]);
  WRITELN('element written through VAR: ', a[2]);
  Show(a[2]);
END;

BEGIN
  Run;
END.
