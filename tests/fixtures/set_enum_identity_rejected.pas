PROGRAM SetEnumIdentityRejected(OUTPUT);
TYPE Color = (red, blue);
     Shade = (light, dark);
     Colors = SET OF Color;
     Shades = SET OF Shade;
     Box = RECORD bits: Colors END;
     Boxes = ARRAY [0..1] OF Box;
     ColorPtr = ^Colors;
VAR c: Colors; s: Shades; r: Box; a: Boxes; p: ColorPtr;
FUNCTION Wrong: Colors;
BEGIN Wrong := s END;
PROCEDURE Take(x: Colors);
BEGIN END;
BEGIN
  c := s;
  r.bits := s;
  a[0].bits := s;
  NEW(p);
  p^ := s;
  Take(s);
  c := [light];
  WRITELN(c = s, ' ', s = c, ' ', c + s = c,
          ' ', red IN s, ' ', light IN c);
  DISPOSE(p)
END.
