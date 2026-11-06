{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE value must be INTEGER, WORD, CHAR, BOOLEAN, REAL or an enumeration }
PROGRAM bad; VAR s: LSTRING(4); BEGIN WRITELN(ENCODE(s, 'ab')) END.
