{ SCANEQ/SCANNE argument validation: source type. }
{ DIALECT: vintage extended }
{ CHECK-FAIL: SCANEQ/SCANNE source must be STRING or LSTRING }
PROGRAM bad; BEGIN WRITELN(SCANNE(1, 'x', 1, 1)) END.
