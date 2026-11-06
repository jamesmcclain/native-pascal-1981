{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE destination must be a bare LSTRING variable at line 3 column 46 }
PROGRAM bad; VAR f: STRING(4); BEGIN WRITELN(ENCODE(f, 1)) END.
