{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE destination must be a bare LSTRING variable }
PROGRAM bad; VAR a: ARRAY [1..2] OF LSTRING(4); BEGIN WRITELN(ENCODE(a[1], 1)) END.
