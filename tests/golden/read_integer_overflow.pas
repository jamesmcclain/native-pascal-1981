{ DIALECT: vintage }
{ 65536 used to wrap to 0 in the 16-bit INTEGER; it is now an error. }
PROGRAM ReadIntegerOverflow(input, output);
VAR n: INTEGER;
BEGIN READLN(n); WRITELN(n) END.
