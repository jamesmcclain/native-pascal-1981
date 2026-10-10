{ DIALECT: vintage extended }
{ OPT: 0 1 2 3 }
PROGRAM positn_literals_initck;
PROCEDURE run;
VAR i: INTEGER;
BEGIN
  {$INITCK+} i := 2;
  WRITELN(POSITN('ab', 'abab', i), ' ', POSITN('a', 'ba', i), ' ', POSITN('', '', i))
END;
BEGIN run END.
