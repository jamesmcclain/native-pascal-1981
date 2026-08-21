{ Plain-Pascal (non-[C]) analog of c_aggregate_return.pas/c_coerced_aggregate.pas:
  exercises the same SysV byval/sret/coerced classification, now applied to
  ordinary PROCEDURE/FUNCTION declarations instead of [C] FOREIGN ones. There
  is no external C reference to cross-check against here (both caller and
  callee are this same compiler's own output), so this test instead checks
  Pascal by-value semantics survive the conversion: a callee mutating its own
  copy of a byval/sret-passed aggregate must never affect the caller's. }
PROGRAM PlainAggregateByvalSret(output);
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
  Str255 = LSTRING(255);

{ MEMORY class (20 bytes > 16): zero real parameters, sret is the only
  LLVM argument. }
FUNCTION BigConst: Big;
VAR
  r: Big;
BEGIN
  r.a := 1; r.b := 2; r.c := 3; r.d := 4; r.e := 5;
  BigConst := r;
END;

{ MEMORY class in AND out, plus a scalar parameter: exercises the sret
  index shift on a non-empty argument list, and mutates its own copy. }
FUNCTION BigScale(b: Big; k: INTEGER32): Big;
BEGIN
  b.a := b.a * k; b.b := b.b * k; b.c := b.c * k; b.d := b.d * k; b.e := b.e * k;
  BigScale := b;
END;

{ COERCED class (8 bytes, one INTEGER eightbyte). }
FUNCTION PairMake(a, b: INTEGER32): Pair;
VAR
  r: Pair;
BEGIN
  r.a := a; r.b := b;
  PairMake := r;
END;

{ byval MEMORY-class param: mutating the parameter must not leak back into
  the caller's own Str255. }
PROCEDURE MutateStr(s: Str255);
BEGIN
  s := 'mutated';
  WRITELN('inside: ', s);
END;

VAR
  g, h: Big;
  p: Pair;
  outer: Str255;
BEGIN
  g := BigConst;
  WRITELN(g.a, ' ', g.b, ' ', g.c, ' ', g.d, ' ', g.e);

  h := BigScale(g, 10);
  WRITELN(h.a, ' ', h.b, ' ', h.c, ' ', h.d, ' ', h.e);
  { g itself must be untouched by BigScale's own mutation of its copy. }
  WRITELN(g.a, ' ', g.b, ' ', g.c, ' ', g.d, ' ', g.e);

  p := PairMake(11, 22);
  WRITELN(p.a, ' ', p.b);

  outer := 'original';
  MutateStr(outer);
  WRITELN('outer after: ', outer);
END.
