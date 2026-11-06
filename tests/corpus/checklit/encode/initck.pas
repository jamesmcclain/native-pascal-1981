{ DIALECT: vintage extended }
{ CHECK-FAIL: INITCK unsupported boundary: call consumer at line 6 column 23 }
PROGRAM encode_initck;
{$INITCK+}
PROCEDURE run; VAR s: LSTRING(8); i: INTEGER;
BEGIN i := 5; WRITELN(ENCODE(s, i), s) END;
BEGIN run END.
