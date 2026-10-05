{ DIALECT: extended }
{ A [C] FOREIGN FUNCTION returning a RECORD by value. Both SysV return
  classes are exercised: MEMORY class (>16 bytes -- the result is written
  through a hidden sret pointer the caller passes as LLVM argument 0, and
  the LLVM call itself returns void) and COERCED class (<=16 bytes -- the
  result comes back in one or two registers and is reassembled into real
  storage here). The C callees (c_aggregate_return.c) are compiled by clang
  from the equivalent struct declarations, so a wrong sret/register choice
  shows up as a wrong printed number, not merely as odd IR. }
PROGRAM CAggregateReturn(output);
TYPE
  Big = RECORD
    a: INTEGER32;
    b: INTEGER32;
    c: INTEGER32;
    d: INTEGER32;
    e: INTEGER32;
  END;
  Pair = RECORD
    a: INTEGER32;
    b: INTEGER32;
  END;
  Wide = RECORD
    lo: INTEGER64;
    hi: INTEGER32;
  END;
  FPair = RECORD
    x: REAL32;
    y: REAL32;
  END;
  DPair = RECORD
    u: REAL;
    v: REAL;
  END;
  Mixed = RECORD
    n: INTEGER32;
    d: REAL;
  END;

{ MEMORY class, and with no real parameters at all: the sret pointer is the
  only LLVM argument the call carries. }
FUNCTION big_const: Big [C]; EXTERN;
{ MEMORY class with both an aggregate and a scalar parameter, so the sret
  pointer's index shift is visible on a non-empty argument list. }
FUNCTION big_scale(b: Big; k: INTEGER32): Big [C]; EXTERN;
FUNCTION pair_make(a: INTEGER32; b: INTEGER32): Pair [C]; EXTERN;
FUNCTION wide_make(hi: INTEGER32): Wide [C]; EXTERN;
FUNCTION fpair_make: FPair [C]; EXTERN;
FUNCTION dpair_make: DPair [C]; EXTERN;
FUNCTION mixed_make(n: INTEGER32): Mixed [C]; EXTERN;

VAR
  g, h: Big;
  p: Pair;
  w: Wide;
  fp: FPair;
  dp: DPair;
  m: Mixed;
BEGIN
  { MEMORY class, zero real parameters. }
  g := big_const;
  WRITELN(g.a, ' ', g.b, ' ', g.c, ' ', g.d, ' ', g.e);

  { MEMORY class, aggregate-in / aggregate-out. Big is 20 bytes, so the
    parameter is byval MEMORY class as well. }
  h := big_scale(g, 10);
  WRITELN(h.a, ' ', h.b, ' ', h.c, ' ', h.d, ' ', h.e);

  { COERCED class, one INTEGER eightbyte. }
  p := pair_make(11, 22);
  WRITELN(p.a, ' ', p.b);

  { COERCED class, two eightbytes: i64 then a half-used i32. }
  w := wide_make(7);
  WRITELN(w.lo, ' ', w.hi);

  { COERCED class, one SSE eightbyte holding two packed floats. }
  fp := fpair_make;
  WRITELN(TRUNC(fp.x * 100.0), ' ', TRUNC(fp.y * 100.0));

  { COERCED class, two SSE eightbytes, each a double. }
  dp := dpair_make;
  WRITELN(TRUNC(dp.u * 100.0), ' ', TRUNC(dp.v * 100.0));

  { COERCED class, an INTEGER eightbyte then an SSE one. }
  m := mixed_make(9);
  WRITELN(m.n, ' ', TRUNC(m.d * 100.0));
END.
