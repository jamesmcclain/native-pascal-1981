{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE value must be INTEGER, WORD, CHAR, BOOLEAN, REAL or an enumeration }
PROGRAM bad; VAR s: LSTRING(20); p: ^INTEGER; BEGIN NEW(p); WRITELN(ENCODE(s, p)) END.
