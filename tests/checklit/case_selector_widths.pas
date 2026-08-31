{ DIALECT: extended }
{ Each CASE label is compared at the SELECTOR's own LLVM width: the labels
  below are all bare INTEGER literals (i16), so a missing coercion would
  either compare at i16 or fail LLVM verification against the wider
  selector. One icmp per label, plus the CHAR and BOOLEAN widths. }
{ CHECK: icmp eq i8 }
{ CHECK: icmp eq i16 }
{ CHECK: icmp eq i32 }
{ CHECK: icmp eq i64 }
{ CHECK: icmp eq i1 }
PROGRAM CaseSelectorWidths(output);
VAR
  i8: INTEGER8;
  i16: INTEGER;
  i32: INTEGER32;
  i64: INTEGER64;
  b: BOOLEAN;
BEGIN
  i8 := 1;
  CASE i8 OF 1: WRITELN('a') OTHERWISE WRITELN('z') END;
  i16 := 1;
  CASE i16 OF 1: WRITELN('b') OTHERWISE WRITELN('z') END;
  i32 := 1;
  CASE i32 OF 1: WRITELN('c') OTHERWISE WRITELN('z') END;
  i64 := 1;
  CASE i64 OF 1: WRITELN('d') OTHERWISE WRITELN('z') END;
  b := TRUE;
  CASE b OF TRUE: WRITELN('e') OTHERWISE WRITELN('z') END
END.
