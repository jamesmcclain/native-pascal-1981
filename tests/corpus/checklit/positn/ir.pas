{ DIALECT: vintage extended }
{ CHECK: declare i32 @positn_from(ptr, i32, ptr, i32, i32) }
{ CHECK: call i32 @positn_from( }
{ CHECK-NOT: call i32 @positn( }
{ CHECK-ASSEMBLE: ir }
PROGRAM positn_ir;
{$INITCK-}
VAR p: LSTRING(2); s: STRING(6); i: INTEGER;
BEGIN p := 'ab'; s := 'ababab'; i := 3; WRITELN(POSITN(p, s, i)) END.
