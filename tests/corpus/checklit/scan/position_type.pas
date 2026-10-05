{ SCANEQ/SCANNE argument validation: position type. }
{ DIALECT: vintage extended }
{ CHECK-FAIL: SCANEQ/SCANNE count and position must be INTEGER }
PROGRAM bad; BEGIN WRITELN(SCANEQ(1, 'x', 'abc', TRUE)) END.
