{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE expects exactly two arguments (D, X) at line 3 column 47 }
PROGRAM bad; VAR s: LSTRING(4); BEGIN WRITELN(ENCODE(s, 1, 2)) END.
