{ DIALECT: vintage extended }
{ CHECK-FAIL: POSITN pattern and source must be STRING or LSTRING }
PROGRAM bad; BEGIN WRITELN(POSITN(1, 'abab', 1)) END.
