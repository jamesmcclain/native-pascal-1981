{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: POSITN fixed STRING source capacity exceeds INTEGER maximum 32767 }
PROGRAM source_capacity;
{$INITCK-}
VAR s: STRING(32768);
BEGIN WRITELN(POSITN('b', s, 1)) END.
