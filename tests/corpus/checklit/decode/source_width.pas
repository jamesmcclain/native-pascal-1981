{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE source takes no field width }
PROGRAM bad; VAR s: LSTRING(4); i: INTEGER; BEGIN WRITELN(DECODE(s:2, i)) END.
