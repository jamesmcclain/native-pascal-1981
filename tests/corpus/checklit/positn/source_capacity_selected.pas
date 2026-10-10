{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: POSITN fixed STRING source capacity exceeds INTEGER maximum 32767 }
PROGRAM source_capacity_selected;
{$INITCK-}
VAR a: ARRAY [1..2] OF STRING(40000);
BEGIN WRITELN(POSITN('b', a[2], 1)) END.
