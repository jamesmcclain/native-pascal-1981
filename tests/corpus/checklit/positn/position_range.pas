{ DIALECT: vintage extended }
{ CHECK-FAIL: Positive integer constant out of range for INTEGER }
PROGRAM bad; BEGIN WRITELN(POSITN('ab', 'abab', 40000)) END.
