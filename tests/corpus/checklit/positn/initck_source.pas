{ DIALECT: vintage extended }
{ CHECK-FAIL: INITCK unsupported boundary: global or captured storage at line }
PROGRAM bad;
{$INITCK-} VAR s: LSTRING(4);
BEGIN s := 'abab'; WRITELN(POSITN('ab', {$INITCK+} s, {$INITCK-} 1)) END.
