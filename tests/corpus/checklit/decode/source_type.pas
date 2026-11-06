{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE source must be STRING or LSTRING at line 3 column 44 }
PROGRAM bad; VAR i: INTEGER; BEGIN WRITELN(DECODE(i, i)) END.
