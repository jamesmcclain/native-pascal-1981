{ DIALECT: vintage extended }
{ CHECK-FAIL: codegen: POSITN fixed STRING source capacity exceeds INTEGER maximum 32767 }
PROGRAM source_capacity_result;
{$INITCK-}
TYPE LargeText = STRING(40000);
VAR storage: LargeText;
FUNCTION Source: LargeText;
BEGIN Source := storage END;
BEGIN WRITELN(POSITN('b', Source(), 1)) END.
