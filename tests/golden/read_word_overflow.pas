{ DIALECT: vintage }
{ 4294967296 used to be narrowed to a 32-bit 0 before the WORD range check. }
PROGRAM ReadWordOverflow(input, output);
VAR w: WORD;
BEGIN READLN(w); WRITELN(w) END.
