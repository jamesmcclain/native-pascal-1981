PROGRAM SetMetadataPaths(OUTPUT);
CONST Yes = TRUE;
TYPE
  Bits = SET OF BOOLEAN;
  AliasBits = Bits;
  Box = RECORD bits: AliasBits END;
  Boxes = ARRAY [0..1] OF Box;
  BoxPtr = ^Box;
  BitArray = ARRAY [0..1] OF AliasBits;
  BitPtr = ^AliasBits;
VAR
  b: Bits;
  r: Box;
  a: Boxes;
  p: BoxPtr;
  q: BitPtr;
  slots: BitArray;

FUNCTION Echo(x: AliasBits): Bits;
BEGIN
  Echo := x
END;

PROCEDURE Store(x: Bits);
BEGIN
  r.bits := x
END;

BEGIN
  b := [Yes];
  Store(Echo(b));
  a[0].bits := Echo(r.bits + []);
  a[1].bits := a[0].bits;
  slots[0] := a[1].bits;
  slots[1] := Echo(slots[0] + []);
  NEW(q);
  q^ := Echo(slots[1]);
  NEW(p);
  p^.bits := Echo(a[1].bits);
  WITH p^ DO bits := Echo(bits + []);
  WITH r DO bits := Echo(p^.bits);
  WRITELN('paths ', TRUE IN r.bits, ' ', TRUE IN a[1].bits,
          ' ', TRUE IN p^.bits, ' ', TRUE IN Echo(Echo(b)),
          ' ', TRUE IN slots[1], ' ', TRUE IN q^);
  DISPOSE(p);
  DISPOSE(q)
END.
