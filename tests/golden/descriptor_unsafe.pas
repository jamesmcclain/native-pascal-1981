{ DIALECT: extended }
PROGRAM DescriptorUnsafe(output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER32; PCells = ^Cells;
VAR backing: ARRAY [2..4] OF INTEGER32; p, q, native: PCells;
    raw: CPTR; calls: INTEGER;
FUNCTION RawOnce: CPTR;
BEGIN calls := calls + 1; RawOnce := ADR backing END;
FUNCTION BoundOnce(n: INTEGER): INTEGER;
BEGIN calls := calls + 1; BoundOnce := n END;
PROCEDURE free(raw: CPTR) [C]; EXTERN;
BEGIN
  backing[2] := 12; backing[4] := 14;
  calls := 0;
  p := UNSAFESUPER(PCells, RawOnce(), BoundOnce(2), BoundOnce(4));
  WRITELN(LOWER(p^), ' ', UPPER(p^), ' ', p^[2], ' ', p^[4], ' ', calls);
  p^[3] := 13; WRITELN(backing[3]);
  raw := UNSAFERAW(p);
  q := UNSAFESUPER(PCells, raw, 2, 3);
  WRITELN(p = q, ' ', UPPER(p^), ' ', UPPER(q^));
  WRITELN(UPPER(UNSAFESUPER(PCells, raw, 2, 4)^));
  q := NIL; WRITELN(UNSAFERAW(q));
  { Exporting a native allocation exposes precisely the malloc/free base. }
  NEW(native, 6); native^[6] := 16;
  raw := UNSAFERAW(native);
  q := UNSAFESUPER(PCells, raw, 2, 6);
  WRITELN(UPPER(q^), ' ', q^[6]);
  DISPOSE(q); { exclusive free right; native is now a dangling alias }
  NEW(native, 3); raw := UNSAFERAW(native); free(raw)
END.
