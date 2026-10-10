{ DIALECT: vintage extended }
{ CHECK-FAIL: POSITN pattern and source must be STRING or LSTRING }
PROGRAM bad; VAR c: CHAR;
BEGIN c := 'a'; WRITELN(POSITN(c, 'abab', 1)) END.
