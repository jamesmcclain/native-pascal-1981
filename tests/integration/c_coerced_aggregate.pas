{ A [C] FOREIGN routine taking a <=16-byte RECORD by value: SysV COERCED
  class, so the record travels in one or two registers instead of a byval
  memory copy. The C callees (c_coerced_aggregate.c) are compiled by clang
  from the equivalent struct declarations, so a wrong register/eightbyte
  choice here shows up as a wrong printed number, not merely as odd IR. }
PROGRAM CCoercedAggregate(output);
TYPE
  Pair = RECORD
    a: INTEGER32;
    b: INTEGER32;
  END;
  FPair = RECORD
    x: REAL32;
    y: REAL32;
  END;
  DPair = RECORD
    u: REAL;
    v: REAL;
  END;
  Wide = RECORD
    lo: INTEGER64;
    hi: INTEGER32;
  END;
  Mixed = RECORD
    n: INTEGER32;
    f: REAL32;
    d: REAL;
  END;

FUNCTION pair_sum(p: Pair): CINT [C]; EXTERN;
FUNCTION fpair_sum(p: FPair): CINT [C]; EXTERN;
FUNCTION dpair_sum(p: DPair): CINT [C]; EXTERN;
FUNCTION wide_sum(w: Wide): CINT [C]; EXTERN;
FUNCTION mixed_sum(m: Mixed): CINT [C]; EXTERN;

VAR
  p: Pair;
  fp: FPair;
  dp: DPair;
  w: Wide;
  m: Mixed;
BEGIN
  { One integer eightbyte. }
  p.a := 100;
  p.b := 23;
  WRITELN(pair_sum(p));

  { One SSE eightbyte holding two packed floats (<2 x float>). }
  fp.x := 10.0;
  fp.y := 4.0;
  WRITELN(fpair_sum(fp));

  { Two SSE eightbytes, each a double. }
  dp.u := 1000.0;
  dp.v := 24.0;
  WRITELN(dpair_sum(dp));

  { Two integer eightbytes, the second only half used. The first is built
    up by arithmetic rather than written as a literal: an integer literal
    is INTEGER (16-bit) in this dialect, so a wide constant cannot be
    spelled directly. }
  w.lo := 30000;
  w.lo := w.lo * 1000;
  w.hi := 5;
  WRITELN(wide_sum(w));

  { An INTEGER+SSE mix in the first eightbyte (which merges to INTEGER)
    plus a double in the second. }
  m.n := 7;
  m.f := 2.0;
  m.d := 33.0;
  WRITELN(mixed_sum(m));
END.
