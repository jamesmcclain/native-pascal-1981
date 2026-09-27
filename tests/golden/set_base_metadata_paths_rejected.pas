PROGRAM SetBaseMetadataPathsRejected(OUTPUT);
TYPE IntSet = SET OF 0..9; BoolSet = SET OF BOOLEAN;
     Box = RECORD bits: BoolSet END;
     Boxes = ARRAY[0..1] OF Box;
     BoolPtr = ^BoolSet;
VAR s: IntSet; bs: BoolSet; r: Box; a: Boxes; p: BoolPtr;
FUNCTION GetBool: BoolSet;
BEGIN GetBool := [TRUE] END;
FUNCTION EchoBool(x: BoolSet): BoolSet;
BEGIN EchoBool := x END;
FUNCTION WrongResult: IntSet;
BEGIN WrongResult := GetBool END;
PROCEDURE AcceptInt(x: IntSet);
BEGIN END;
PROCEDURE AcceptVarInt(VAR x: IntSet);
BEGIN END;
BEGIN
  r.bits := s;
  a[0].bits := s;
  NEW(p);
  p^ := s;
  WITH r DO bits := s;
  AcceptInt(bs);
  AcceptVarInt(bs);
  bs := EchoBool(s);
  s := GetBool;
  s := GetBool();
  s := [TRUE] + [];
  s := [] + [TRUE];
  WRITELN(r.bits = s, ' ', 1 IN p^);
  DISPOSE(p)
END.
