{ DIALECT: extended }
{ OPT: 0 }
{ CHECK: define void @MakeBig(ptr noalias sret([70001 x i8]) }
{ CHECK: call void @llvm.memset.p0.i64(ptr align 1 %0, i8 0, i64 70001 }
{ CHECK: call void @llvm.memmove.p0.p0.i64(ptr align 1 @s, ptr align 1 }
{ CHECK: i64 70001, i1 false) }
{ CHECK-NOT: load [70001 x i8] }
{ CHECK-NOT: store [70001 x i8] }
{ CHECK: load [11 x i8], ptr @small }
{ CHECK: store [11 x i8] }
{ CHECK-ASSEMBLE: ir }
PROGRAM LargeAggregateCopies(output);
{ NEW-35: an aggregate of 1,024 bytes or more is never a first-class LLVM
  value in a whole copy: the sret result slot is zeroed with memset and the
  result is copied out with memmove. A small aggregate keeps its
  first-class load and store. }
VAR
  s: LSTRING(70000);
  small, other: LSTRING(10);

FUNCTION MakeBig: LSTRING(70000);
BEGIN
  MakeBig := 'big';
END;

BEGIN
  s := MakeBig;
  small := 'abc';
  other := small;
  WRITELN(s, other);
END.
