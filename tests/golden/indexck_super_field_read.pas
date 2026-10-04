{ DIALECT: extended }
PROGRAM indexck_super_field_read(OUTPUT);
{ The guard follows the descriptor through record and array slots; the
  check uses the selected descriptor's own upper, not the sibling's. }
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
     Holder = RECORD a, b: P END;
VAR h: Holder; slots: ARRAY [0..1] OF P; i: INTEGER;
BEGIN
  NEW(h.a, 4); NEW(h.b, 9);
  NEW(slots[0], 4); NEW(slots[1], 9);
  i := 9;
  h.a^[2] := 22; h.b^[i] := 99; slots[0]^[4] := 44; slots[1]^[9] := 11;
  WRITELN(h.a^[2], ' ', h.b^[9], ' ', slots[0]^[4], ' ', slots[1]^[9]);
  i := 5;
  WRITELN(h.a^[i]) { h.a's actual upper is 4 }
END.
