INTERFACE;
UNIT mismatchconsttypes (OkInt, OkReal, OkStr, OkChar, OkEnum, BadReal, BadStr, BadChar, BadEnum, BadKind, Show);

TYPE Color = (Red, Green, Blue);

CONST
  OkInt = 10;
  OkReal = 1.5;
  OkStr = 'hello';
  OkChar = 'a';
  OkEnum = Green;
  BadReal = 1.5;
  BadStr = 'hello';
  BadChar = 'a';
  BadEnum = Red;
  BadKind = 10;

PROCEDURE Show;

END;
