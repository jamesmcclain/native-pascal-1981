{ DIALECT: vintage extended }
{ CHECK: declare i32 @pas_decode_integer(ptr, i32, i32, i32, i32, i64, i64, ptr) }
{ CHECK: declare i32 @pas_decode_enum(ptr, i32, ptr, i32, i32, ptr) }
{ CHECK: declare i32 @pas_decode_char(ptr, i32, i32, i32, ptr) }
{ CHECK: declare i32 @pas_decode_real(ptr, i32, ptr) }
{ CHECK: call i32 @pas_decode_integer(ptr getelementptr ([7 x i8], ptr @s, i32 0, i32 1), i32 % }
{ CHECK: i32 16, i32 0, i32 1, i64 1, i64 9, ptr }
{ CHECK: call i32 @pas_decode_enum( }
{ CHECK: call i32 @pas_decode_char( }
{ CHECK: call i32 @pas_decode_real( }
{ CHECK-NOT: @decode_value }
{ CHECK-NOT: call i32 @pas_read_ }
{ CHECK-ASSEMBLE: ir }
PROGRAM decode_ir;
{$INITCK-}
TYPE small = 1..9;
VAR s: LSTRING(6); n: small; b: BOOLEAN; c: CHAR; r: REAL;
BEGIN
  s := '55';
  WRITELN(DECODE(s, n), DECODE(s, b), DECODE(s, c), DECODE(s, r))
END.
