{ SCANEQ/SCANNE argument validation: arity. }
{ DIALECT: vintage extended }
{ CHECK-FAIL: SCANEQ/SCANNE expects exactly four arguments }
PROGRAM bad; BEGIN WRITELN(SCANEQ(1, 'x', 'abc')) END.
