{ CHECK: define void @TakesStr(ptr byval([256 x i8]) align 8 %0) }
{ CHECK: define void @MakeStr(ptr noalias sret([256 x i8]) align 8 %0) }
PROGRAM ByvalSretPlainCheck(output);
TYPE
  Str255 = LSTRING(255);
PROCEDURE TakesStr(s: Str255);
BEGIN
  WRITELN(s);
END;
FUNCTION MakeStr: Str255;
VAR
  res: Str255;
BEGIN
  res := 'hello';
  MakeStr := res;
END;
VAR
  msg: Str255;
BEGIN
  msg := MakeStr;
  TakesStr(msg);
END.
