{ Initialized ABI/layout release probe. Aggregate/descriptor results remain
  unchecked boundaries, not a claim of INITCK result coverage. }
{$INITCK+}
PROGRAM InitckValidationABI(output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER;
     PCells = ^Cells;
     Holder = RECORD data: PCells END;
     Pair = RECORD first, second: PCells END;
PROCEDURE Observe(src: PCells);
BEGIN WRITELN(LOWER(src^), ':', UPPER(src^), ':', src^[2]) END;
PROCEDURE Rebind(VAR dest: PCells; src: PCells);
BEGIN dest := src END;
PROCEDURE View(CONST src: Holder);
BEGIN WRITELN(UPPER(src.data^), ':', src.data^[4]) END;
PROCEDURE TakePair(src: Pair);
BEGIN WRITELN(UPPER(src.first^), ':', UPPER(src.second^)) END;
{$INITCK-}
FUNCTION Echo(src: PCells): PCells;
BEGIN Echo := src END;
FUNCTION EchoHolder(src: Holder): Holder;
BEGIN EchoHolder := src END;
FUNCTION ReturnPair(src: Pair): Pair;
BEGIN ReturnPair := src END;
{$INITCK+}
FUNCTION Scalar(src: INTEGER): INTEGER;
BEGIN Scalar := src END;
PROCEDURE Probe;
VAR p, q, alias: PCells; h: Holder; pairslot: Pair;
BEGIN
  NEW(p, 4); NEW(q, 6);
  p^[2] := -32768; p^[4] := 0; q^[2] := 12; q^[6] := 16;
  alias := p; h.data := p;
  pairslot.first := p; pairslot.second := q;
  Observe(alias); View(h); TakePair(pairslot);
  Rebind(alias, q); Observe(alias);
  { These initialized result transfers cross the documented unsupported
    result boundary with checking disabled at the consuming call. }
  {$INITCK-}
  alias := Echo(p); h := EchoHolder(h); pairslot := ReturnPair(pairslot);
  {$INITCK+}
  Observe(alias); View(h); TakePair(pairslot);
  WRITELN(Scalar(0), ':', Scalar(-32768));
  WRITELN(SIZEOF(p), ':', SIZEOF(h), ':', SIZEOF(pairslot));
  DISPOSE(p); DISPOSE(q)
END;
BEGIN Probe END.
