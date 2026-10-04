PROGRAM mixedok;
TYPE Pair = RECORD x, y: INTEGER END;
PROCEDURE put(VAR n: INTEGER; v: INTEGER);
BEGIN {$INITCK-} n := v END;
PROCEDURE relay(VAR p: Pair; v: INTEGER);
BEGIN put(p.x, v) END;
FUNCTION first(CONST p: Pair): INTEGER;
BEGIN {$INITCK+} first := p.x END;
FUNCTION total(p: Pair): INTEGER;
BEGIN {$INITCK+} total := p.x + p.y END;
PROCEDURE probe(v: INTEGER);
VAR a, b: Pair; cells: ARRAY [1..2] OF Pair;
BEGIN
  {$INITCK-} relay(a, v); b := a;
  {$INITCK+} WRITELN(first(b));
  {$PUSH} {$INITCK-} put(b.y, 2); {$POP}
  WRITELN(total(b));
  {$DEBUG+} {$INITCK-} relay(cells[2], v);
  {$INITCK+} WITH cells[2] DO WRITELN(x);
  put(cells[2].y, 3);
  WRITELN(total(cells[2]))
END;
BEGIN probe(0); probe(-32768) END.
