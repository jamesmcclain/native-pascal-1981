{ DIALECT: vintage extended }
{ CHECK-FAIL: Field width specifier is not allowed in a call to the user-declared DECODE }
PROGRAM bad;
FUNCTION DECODE(x: INTEGER): INTEGER;
BEGIN DECODE := x + 1 END;
BEGIN WRITELN(DECODE(6:2)) END.
