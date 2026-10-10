{ DIALECT: extended }
{ CHECK-FAIL: POSITN position must be INTEGER }
PROGRAM bad; VAR i: INTEGER32;
BEGIN i := 1; WRITELN(POSITN('ab', 'abab', i)) END.
