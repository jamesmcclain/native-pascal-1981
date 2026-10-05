{ DIALECT: extended }
PROGRAM SuperNewHardened(output);
TYPE Cells = SUPER ARRAY [-3..*] OF INTEGER; P = ^Cells;
     Triple = VECTOR [4] OF INTEGER32;
     Triples = SUPER ARRAY [2..*] OF Triple; PT = ^Triples;
VAR slots: ARRAY [0..1] OF P; aliasp: P; vectors: PT; v: Triple; calls, selections: INTEGER;
FUNCTION Pick: INTEGER;
BEGIN selections := selections + 1; Pick := 1 END;
FUNCTION BoundVal: INTEGER64;
BEGIN calls := calls + 1; BoundVal := -1 END;
BEGIN
  NEW(slots[Pick()], BoundVal);
  slots[1]^[-3] := 11; slots[1]^[-1] := 33; aliasp := slots[1];
  NEW(slots[1], 0); slots[1]^[0] := 44;
  WRITELN(calls, ' ', selections, ' ', UPPER(aliasp^), ' ', UPPER(slots[1]^));
  WRITELN(aliasp^[-3], ' ', aliasp^[-1], ' ', slots[1]^[0]);
  NEW(vectors, 3); vectors^[2] := VSPLAT(7, Triple); vectors^[3] := VSPLAT(9, Triple);
  v := vectors^[2]; WRITE(v[2], ' '); v := vectors^[3]; WRITELN(v[0]);
  DISPOSE(vectors); DISPOSE(aliasp); DISPOSE(slots[1])
END.
