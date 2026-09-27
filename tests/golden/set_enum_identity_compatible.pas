PROGRAM SetEnumIdentityCompatible(OUTPUT);
TYPE Color = (red, green, blue);
     ColorAlias = Color;
     ColorRange = red..blue;
     Colors = SET OF Color;
     ColorSlice = SET OF ColorRange;
     ExplicitSlice = SET OF green..blue;
     Box = RECORD bits: Colors END;
     Boxes = ARRAY [0..1] OF Box;
     ColorPtr = ^Colors;
CONST Pick = green;
VAR c: Colors; d: ColorSlice; e: ExplicitSlice; r: Box; a: Boxes; p: ColorPtr;
FUNCTION Echo(x: Colors): Colors;
BEGIN Echo := x END;
BEGIN
  c := [red, Pick, blue];
  d := [green..blue];
  e := [green..blue];
  c := d + e + [];
  r.bits := Echo(c);
  a[0].bits := r.bits;
  NEW(p);
  p^ := a[0].bits;
  IF (Pick IN p^) AND (c = d) AND ([] <> c) AND (c <> []) THEN
    WRITELN('enum host');
  DISPOSE(p)
END.
