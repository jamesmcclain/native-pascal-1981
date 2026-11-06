{ DIALECT: vintage extended }
{ CHECK-FAIL: ENCODE field width must be INTEGER }
{ CHECK-FAIL: ENCODE precision must be INTEGER }
PROGRAM bad; VAR s: LSTRING(4); r: REAL; BEGIN r := 1.0; WRITELN(ENCODE(s, r:r:'a')) END.
