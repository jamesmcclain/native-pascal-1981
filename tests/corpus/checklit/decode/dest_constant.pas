{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE destination must be a variable }
PROGRAM bad; CONST k = 5; BEGIN WRITELN(DECODE('1', k)) END.
