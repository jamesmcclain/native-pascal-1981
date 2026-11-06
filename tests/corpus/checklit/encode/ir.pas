{ DIALECT: vintage extended }
{ CHECK: declare i32 @pas_encode_fmt(ptr, i32, ptr, ptr, ...) }
{ CHECK: call i32 (ptr, i32, ptr, ptr, ...) @pas_encode_fmt( }
{ CHECK-NOT: @encode_value }
{ CHECK-ASSEMBLE: ir }
PROGRAM encode_ir;
{$INITCK-}
VAR s: LSTRING(6); i: INTEGER;
BEGIN i := 3; WRITELN(ENCODE(s, i:4), s) END.
