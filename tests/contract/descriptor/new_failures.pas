{ DIALECT: extended }
PROGRAM NewFailures(input, output);
{$INDEXCK-}
TYPE Cells = SUPER ARRAY [2..*] OF INTEGER; P = ^Cells;
VAR slots: ARRAY [0..1] OF P; evaluations, selections, testmode: INTEGER32;
PROCEDURE Arm(m: INTEGER32) [C]; EXTERN;
FUNCTION Pick: INTEGER;
BEGIN selections := selections + 1; Pick := 0 END;
FUNCTION BoundVal: INTEGER64;
BEGIN
  evaluations := evaluations + 1;
  CASE testmode OF
    1: BoundVal := 1;
    2: BoundVal := 40000;
    4: BoundVal := MAXINT64;
    5: BoundVal := 4;
    6: BEGIN slots[0] := NIL; BoundVal := 1 END
  END
END;
FUNCTION UnsignedBound: WORD64;
BEGIN evaluations := evaluations + 1; UnsignedBound := MAXWORD64 END;
BEGIN
  READLN(testmode);
  NEW(slots[0], 4); slots[0]^[2] := 99; slots[1] := NIL;
  Arm(testmode);
  IF testmode = 3 THEN NEW(slots[Pick()], UnsignedBound)
  ELSE NEW(slots[Pick()], BoundVal);
  WRITELN('UNEXPECTED: NEW returned')
END.
