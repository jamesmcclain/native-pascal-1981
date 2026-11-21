{ NEW-44 / NEW-41 / NEW-48 positive cases:
  - Case-insensitive function result assignment (`mixcase := ...`, `buildpair.a := ...`)
  - Enclosing function result assignment from a nested routine
  - Dereferencing a CONST pointer or pointer-returning function is still writable. }
PROGRAM func_result_case_insensitive;
TYPE
  Pair = RECORD
    a, b: INTEGER;
  END;
  IntPtr = ^INTEGER;

VAR
  g: INTEGER;

FUNCTION MixCase: INTEGER;
BEGIN
  mixcase := 10;
  MIXCASE := 42;
END;

FUNCTION OuterFunc: INTEGER;
  PROCEDURE Inner;
  BEGIN
    outerfunc := 77;
  END;
BEGIN
  Inner;
END;

FUNCTION BuildPair: Pair;
BEGIN
  buildpair.a := 3;
  BUILDPAIR.b := 4;
END;

PROCEDURE MutatePointee(CONST p: IntPtr);
BEGIN
  p^ := 99;
END;

FUNCTION GetPtr: IntPtr;
VAR
  p: IntPtr;
BEGIN
  NEW(p);
  p^ := 1;
  getptr := p;
END;

VAR
  pr: Pair;
  ip: IntPtr;
BEGIN
  WRITELN(MixCase);
  WRITELN(OuterFunc);
  pr := BuildPair;
  WRITELN(pr.a, ' ', pr.b);
  NEW(ip);
  ip^ := 0;
  MutatePointee(ip);
  WRITELN(ip^);
  DISPOSE(ip);
  GetPtr^ := 123;
  WRITELN('ok');
END.
