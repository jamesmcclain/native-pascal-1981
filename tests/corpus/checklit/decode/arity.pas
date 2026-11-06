{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE expects exactly two arguments (S, X) at line 3 column 44 }
PROGRAM bad; VAR i: INTEGER; BEGIN WRITELN(DECODE('1', i, i)) END.
