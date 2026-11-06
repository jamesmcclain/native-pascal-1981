{ DIALECT: vintage extended }
{ OPT: 0 2 }
{$INITCK+}
{ NEW-29: binding an uninitialized CHAR to a CONST conformant STRING
  formal reads it at the call, so INITCK fails there. }
PROGRAM SuperStringInitckBad(OUTPUT);

PROCEDURE Show(CONST s: STRING);
BEGIN
  WRITELN('bound with upper ', UPPER(s));
END;

PROCEDURE Run;
VAR
  c: CHAR;
BEGIN
  WRITELN('before');
  Show(c);
  WRITELN('not reached');
END;

BEGIN
  Run;
END.
