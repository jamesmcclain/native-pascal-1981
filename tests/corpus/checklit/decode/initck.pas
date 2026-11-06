{ DIALECT: vintage extended }
{ CHECK-FAIL: INITCK unsupported boundary: call consumer at line 6 column 15 }
PROGRAM decode_initck;
{$INITCK+}
PROCEDURE run; VAR i: INTEGER;
BEGIN WRITELN(DECODE('5', i), i) END;
BEGIN run END.
