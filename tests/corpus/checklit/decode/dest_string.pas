{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE destination must be INTEGER, WORD, CHAR, BOOLEAN, REAL or an enumeration }
PROGRAM bad; VAR s: LSTRING(4); BEGIN WRITELN(DECODE('ab', s)) END.
