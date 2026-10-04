{ DIALECT: vintage }
{ The ends of the INTEGER and WORD ranges still read. }
PROGRAM ReadIntegerLimits(input, output);
VAR a, b: INTEGER; w: WORD;
BEGIN READLN(a, b); READLN(w); WRITELN(a, ' ', b, ' ', w) END.
