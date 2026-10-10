{ DIALECT: vintage extended }
{ CHECK-FAIL: POSITN position must be INTEGER }
PROGRAM bad; BEGIN WRITELN(POSITN('ab', 'abab', TRUE)) END.
