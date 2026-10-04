{ SCANEQ/SCANNE argument validation: count type. }
{ DIALECT: vintage extended }
{ CHECK-FAIL: SCANEQ/SCANNE count and position must be INTEGER }
PROGRAM bad; BEGIN WRITELN(SCANNE(TRUE, 'x', 'abc', 1)) END.
