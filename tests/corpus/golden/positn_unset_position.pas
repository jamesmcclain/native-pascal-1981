{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM positn_unset_position;
{$INITCK+}
PROCEDURE run;
VAR i: INTEGER;
BEGIN
  WRITE('prefix');
  WRITELN(POSITN('', '', i))
END;
BEGIN run END.
