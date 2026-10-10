{ DIALECT: vintage extended }
{ CHECK-FAIL: INITCK unsupported boundary: STRING/LSTRING POSITN operand at line }
PROGRAM bad;
{$INITCK-}
TYPE Text2 = LSTRING(2);
FUNCTION Pattern: Text2;
BEGIN Pattern := 'ab' END;
BEGIN WRITELN(POSITN({$INITCK+} Pattern(), {$INITCK-} 'abab', 1)) END.
