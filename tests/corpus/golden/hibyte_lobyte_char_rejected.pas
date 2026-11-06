{ DIALECT: vintage }
{ HIBYTE and LOBYTE take only INTEGER or WORD arguments. }
PROGRAM hibbad(OUTPUT);
VAR c: CHAR;
BEGIN c := 'a'; WRITELN(HIBYTE(c)) END.
