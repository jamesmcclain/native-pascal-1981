{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE destination takes no field width }
PROGRAM bad; VAR s: LSTRING(4); BEGIN WRITELN(ENCODE(s:2, 1)) END.
