{ DIALECT: vintage extended }
{ CHECK-FAIL: INITCK unsupported boundary: global or captured storage at line }
PROGRAM bad;
{$INITCK-} VAR p: LSTRING(2);
BEGIN p := 'ab'; WRITELN(POSITN({$INITCK+} p, {$INITCK-} 'abab', 1)) END.
