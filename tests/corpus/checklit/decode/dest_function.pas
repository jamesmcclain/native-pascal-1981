{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE destination must be a variable }
PROGRAM bad;
FUNCTION g: INTEGER;
BEGIN g := 1 END;
BEGIN WRITELN(DECODE('1', g)) END.
