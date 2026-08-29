{ DIALECT: extended }
{ COERCED-class aggregates alongside a MEMORY-class one and plain scalars
  in a single [C] call: a COERCED aggregate expands into one LLVM argument
  per eightbyte, so every parameter after it sits at a shifted LLVM index --
  which is exactly what the byval/align attributes on the MEMORY-class
  parameter must still land on. Callees in c_mixed_aggregate.c. }
PROGRAM CMixedAggregate(output);
TYPE
  Pair = RECORD
    a: INTEGER32;
    b: INTEGER32;
  END;
  Big = RECORD
    v: ARRAY [1..8] OF INTEGER32;
  END;
  Trio = ARRAY [1..3] OF INTEGER32;

FUNCTION mixed_call(n: CINT; p: Pair; big: Big; q: Pair; k: CINT): CINT [C]; EXTERN;
FUNCTION trio_sum(t: Trio): CINT [C]; EXTERN;

VAR
  p, q: Pair;
  big: Big;
  t: Trio;
  i: INTEGER32;
BEGIN
  p.a := 1;
  p.b := 2;
  q.a := 30;
  q.b := 40;
  FOR i := 1 TO 8 DO
    big.v[i] := i * 100;
  { 5 + (1+2) + 3600 + (30+40) + 9 = 3687 }
  WRITELN(mixed_call(5, p, big, q, 9));

  { A COERCED ARRAY (12 bytes: an 8-byte integer eightbyte plus a
    half-used second one), not a RECORD. }
  t[1] := 11;
  t[2] := 22;
  t[3] := 33;
  WRITELN(trio_sum(t));
END.
