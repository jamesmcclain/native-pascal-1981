PROGRAM RecordGraph(output);
TYPE
  Inner = RECORD
    val: INTEGER;
  END;
  PInner = ^Inner;
  Wrapper = RECORD
    head: Inner;
    ptr: PInner;
    count: INTEGER;
  END;
FUNCTION malloc(size: CINT): PInner [C]; EXTERN;
PROCEDURE free(p: PInner) [C]; EXTERN;
VAR
  p1, p2: PInner;
  w: Wrapper;
BEGIN
  p1 := malloc(8);
  p2 := malloc(8);
  p1^.val := 1;
  p2^.val := 2;

  w.head.val := 99;
  w.ptr := p1;
  w.count := 3;

  WRITELN(w.head.val);
  WRITELN(w.ptr^.val);
  WRITELN(p2^.val);
  WRITELN(w.count);

  free(p1); free(p2);
END.
