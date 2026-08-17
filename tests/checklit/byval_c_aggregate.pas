{ CHECK: declare void @TakesStr(ptr byval([256 x i8]) align 1) }
PROGRAM ByvalCheck(output);
TYPE
  Str255 = LSTRING(255);
PROCEDURE TakesStr(s: Str255) [C]; EXTERN;
VAR
  msg: Str255;
BEGIN
  msg := 'hello';
END.
