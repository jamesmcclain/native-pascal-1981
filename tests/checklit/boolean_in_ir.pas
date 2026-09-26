{ BOOLEAN IN zero-extends the i1 operand to i16 before the set bit test,
  so TRUE is ordinal 1. The main program uses only variables, so no set
  constructor adds a zext of its own. }
{ CHECK: define i1 @Member(i1 %0, [4 x i64] %1) }
{ CHECK-COUNT: 1 zext i1 % }
{ CHECK: to i16 }
{ CHECK: sext i16 }
{ CHECK: shl i64 1, }
{ CHECK: icmp ne i64 }
{ CHECK-NOT: sext i1 % }
PROGRAM BooleanInIr(OUTPUT);
TYPE BoolSet = SET OF BOOLEAN;
VAR
  flag: BOOLEAN;
  bs: BoolSet;

FUNCTION Member(b: BOOLEAN; s: BoolSet): BOOLEAN;
BEGIN
  Member := b IN s
END;

BEGIN
  flag := TRUE;
  WRITELN(Member(flag, bs))
END.
