{ DIALECT: extended }
PROGRAM DescriptorTransport(output);
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER;
     PCells = ^Cells;
     AliasPtr = PCells;
     Holder = RECORD data: PCells END;
     Slots = ARRAY [0..1] OF PCells;
VAR p, q, resultptr: PCells; alias: AliasPtr;
    h, returned: Holder; a: Slots;
    calls, indexes: INTEGER;
FUNCTION Echo(src: PCells): PCells;
BEGIN Echo := src END;
FUNCTION IsNull(src: PCells): BOOLEAN;
BEGIN IsNull := src = NIL END;
PROCEDURE Rebind(VAR dest: PCells; src: PCells);
BEGIN dest := src END;
FUNCTION EchoHolder(src: Holder): Holder;
BEGIN EchoHolder := src END;
PROCEDURE Observe(src: PCells);
BEGIN WRITELN(LOWER(src^), ' ', UPPER(src^), ' ', src^[2]) END;
FUNCTION Selected(n: INTEGER): PCells;
BEGIN calls := calls + 1; Selected := a[n] END;
FUNCTION SlotIndex: INTEGER;
BEGIN indexes := indexes + 1; SlotIndex := 1 END;
BEGIN
  NEW(p, 4); NEW(q, 9);
  p^[2] := 12; p^[4] := 14; q^[2] := 22; q^[9] := 29;
  alias := p;
  { Replacing p must not change alias's original bound. }
  NEW(p, 6); p^[2] := 32; p^[6] := 36;
  h.data := q; a[0] := alias; a[1] := q;
  WRITELN(UPPER(alias^), ' ', UPPER(q^), ' ', UPPER(p^));
  WRITELN(h.data^[2], ' ', h.data^[9], ' ', a[0]^[4], ' ', a[1]^[9]);
  { Selected writes must target the selected allocation, not the last NEW. }
  h.data^[9] := 39; a[0]^[4] := 44;
  WRITELN(q^[9], ' ', alias^[4]);
  Observe(alias); Observe(q);
  resultptr := Echo(alias); WRITELN(UPPER(resultptr^), ' ', resultptr^[4]);
  Rebind(resultptr, q); WRITELN(UPPER(resultptr^), ' ', resultptr^[9]);
  Rebind(h.data, alias); Rebind(a[0], q);
  WRITELN(UPPER(h.data^), ' ', UPPER(a[0]^));
  returned := EchoHolder(h); WRITELN(UPPER(returned.data^), ' ', returned.data^[4]);
  calls := 0; indexes := 0;
  WRITELN(UPPER(Selected(1)^), ' ', calls);
  WRITELN(UPPER(a[SlotIndex()]^), ' ', indexes);
  resultptr := NIL; WRITELN(resultptr = NIL, ' ', alias = Echo(alias), ' ', alias = q, ' ', IsNull(Echo(NIL)));
  DISPOSE(alias); DISPOSE(q); DISPOSE(p)
END.
