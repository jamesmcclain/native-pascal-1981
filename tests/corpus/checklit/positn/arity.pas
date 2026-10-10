{ DIALECT: vintage extended }
{ CHECK-FAIL: POSITN expects exactly three arguments (P, S, I) }
PROGRAM bad; BEGIN WRITELN(POSITN('ab', 'abab')) END.
