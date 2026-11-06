{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE destination must be a variable }
PROGRAM bad; VAR i: INTEGER; BEGIN WRITELN(DECODE('1', i + 1)) END.
