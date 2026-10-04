{ SCANEQ/SCANNE argument validation: count range. }
{ DIALECT: vintage extended }
{ CHECK-FAIL: out of range }
PROGRAM bad; BEGIN WRITELN(SCANEQ(40000, 'x', 'abc', 1)) END.
