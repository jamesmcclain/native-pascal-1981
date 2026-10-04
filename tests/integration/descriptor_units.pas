{ DIALECT: extended }
(*$INCLUDE:'descriptor_units.api.inc'*)
PROGRAM DescriptorUnits(output);
USES descriptorapi;
TYPE Holder = RECORD data: PCells END;
VAR p, q, alias: PCells; h: Holder;
BEGIN
  WRITELN(shared = NIL);
  NEW(p, 4); NEW(q, 9); p^[4] := 14; q^[9] := 29;
  shared := p; alias := Relay(shared); h.data := alias;
  WRITELN(UPPER(alias^), ' ', alias^[4]);
  Replace(h.data, q); WRITELN(UPPER(h.data^), ' ', h.data^[9], ' ', UPPER(shared^));
  DISPOSE(p); DISPOSE(q)
END.
