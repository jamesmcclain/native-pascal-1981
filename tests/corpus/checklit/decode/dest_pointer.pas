{ DIALECT: vintage extended }
{ CHECK-FAIL: DECODE destination must be INTEGER, WORD, CHAR, BOOLEAN, REAL or an enumeration }
PROGRAM bad; VAR p: ^INTEGER; BEGIN WRITELN(DECODE('1', p)) END.
