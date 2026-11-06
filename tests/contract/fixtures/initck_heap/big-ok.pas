{ DIALECT: extended }
PROGRAM bigok(OUTPUT);
{ A 32 MiB NEW referent is above the heap-state leaf cap: stores through it
  under INITCK+ and reads under INITCK- need no state and no frame-sized
  fallback (before the cap each lookup site reserved 32 MiB of stack).
  The capped element type next to it (exactly 65536 leaves) stays tracked.
  Subscripts above 65535 are INTEGER32 variables, used under INITCK- only
  (INTEGER32 is outside the INITCK slice). }
TYPE Big = ARRAY [0..33554431] OF CHAR;
     PB = ^Big;
     Cap = ARRAY [1..65536] OF CHAR;
     PC = ^Cap;
PROCEDURE fill(p: PB; c: PC);
VAR j: INTEGER; top: INTEGER32;
BEGIN
  {$INITCK+}
  FOR j := 0 TO 25 DO p^[j * 1000] := CHR(ORD('a') + j);
  c^[1] := 'k';
  WRITELN(c^[1]);
  {$INITCK-}
  top := 33554431;
  p^[top] := 'z'
END;
PROCEDURE show(p: PB);
VAR j, n: INTEGER; top: INTEGER32;
BEGIN
  n := 0; top := 33554431;
  FOR j := 0 TO 25 DO
    IF p^[j * 1000] = CHR(ORD('a') + j) THEN n := n + 1;
  WRITELN(n:1, ' ', p^[1000], p^[top])
END;
VAR p: PB; c: PC;
BEGIN
  NEW(p); NEW(c);
  fill(p, c);
  show(p);
  DISPOSE(p); DISPOSE(c)
END.
