{ DIALECT: extended }
{ NEW-23: WRD narrows each source width to i16 with a valid conversion:
  i32 and i64 truncate (a zext to the narrower i16 was invalid IR), an
  INTEGER8 sign-extends, a WORD8 zero-extends. No range check is emitted:
  WRD is unchecked even under RANGECK. The IR must also assemble. }
{ CHECK-ASSEMBLE: ir }
{ CHECK: trunc i32 }
{ CHECK: trunc i64 }
{ CHECK: sext i8 }
{ CHECK: zext i8 }
{ CHECK-NOT: zext i32 }
{ CHECK-NOT: zext i64 }
{ CHECK-NOT: pas_subrange_error }
PROGRAM WrdSourceWidths(OUTPUT);
{$RANGECK+}
VAR
  i8: INTEGER8;
  w8: WORD8;
  i32: INTEGER32;
  i64: INTEGER64;
  w: WORD;
BEGIN
  i8 := -2;
  w8 := 2;
  i32 := 70000;
  i64 := -2;
  w := WRD(i8);
  w := WRD(w8);
  w := WRD(i32);
  w := WRD(i64);
  WRITELN(w)
END.
