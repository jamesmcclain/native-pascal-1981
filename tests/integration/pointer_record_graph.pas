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
VAR
  p1, p2: PInner;
  w: Wrapper;
BEGIN
  NEW(p1); NEW(p2);
  p1^.val := 1;
  p2^.val := 2;

  w.head.val := 99;
  w.ptr := p1;
  w.count := 3;

  WRITELN(w.head.val);
  WRITELN(w.ptr^.val);
  WRITELN(p2^.val);
  WRITELN(w.count);

  DISPOSE(p1);
  DISPOSE(p2);
END.
