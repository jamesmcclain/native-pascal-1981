{ DIALECT: vintage extended }
{ CHECK-FAIL: Field width specifier is not allowed in a call to the user-declared ENCODE }
PROGRAM bad;
FUNCTION ENCODE(x: INTEGER): INTEGER;
BEGIN ENCODE := x + 1 END;
BEGIN WRITELN(ENCODE(6:2)) END.
