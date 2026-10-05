{ SCANEQ/SCANNE argument validation: pattern type. }
{ DIALECT: vintage extended }
{ CHECK-FAIL: SCANEQ/SCANNE pattern must be CHAR }
PROGRAM bad; BEGIN WRITELN(SCANEQ(1, 1, 'abc', 1)) END.
