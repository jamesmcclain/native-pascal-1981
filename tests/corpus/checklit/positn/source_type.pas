{ DIALECT: vintage extended }
{ CHECK-FAIL: POSITN pattern and source must be STRING or LSTRING }
PROGRAM bad; BEGIN WRITELN(POSITN('ab', TRUE, 1)) END.
