{ DIALECT: extended }
PROGRAM heapfail(input, output);
TYPE R = RECORD v, w: INTEGER END;
     PR = ^R;
     Cells = SUPER ARRAY [1..*] OF INTEGER;
     P = ^Cells;
VAR slot: PR; cells: P; keep: ARRAY [1..46] OF PR; mode: INTEGER32; i: INTEGER;
PROCEDURE Arm(m: INTEGER32) [C]; EXTERN;
BEGIN
  READLN(mode);
  NEW(slot); slot^.v := 7; NEW(cells, 2); cells^[1] := 9;
  { Mode 5: 48 registrations, so the next one grows the registry table. }
  IF mode = 5 THEN FOR i := 1 TO 46 DO NEW(keep[i]);
  Arm(mode);
  IF (mode = 3) OR (mode = 4) THEN NEW(cells, 3) ELSE NEW(slot);
  WRITELN('UNEXPECTED: NEW returned')
END.
