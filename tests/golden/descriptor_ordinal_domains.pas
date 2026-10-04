{ DIALECT: extended }
PROGRAM DescriptorOrdinalDomains(output);
CONST c200 = CHR(200); wordlow = 40000;
TYPE Colors = (Red, Green, Blue);
     Bools = SUPER ARRAY [FALSE..*] OF INTEGER; PBools = ^Bools;
     Chars = SUPER ARRAY [c200..*] OF INTEGER; PChars = ^Chars;
     Enums = SUPER ARRAY [Red..*] OF INTEGER; PEnums = ^Enums;
     Words = SUPER ARRAY [wordlow..*] OF INTEGER8; PWords = ^Words;
     Wide = SUPER ARRAY [-32767..*] OF INTEGER8; PWide = ^Wide;
VAR b: PBools; c: PChars; e: PEnums; w: PWords; wideptr: PWide;
    backing: ARRAY [40000..60000] OF INTEGER8;
    widebacking: ARRAY [-32767..32767] OF INTEGER8; i: WORD;
BEGIN
  NEW(b, TRUE); NEW(c, CHR(201)); NEW(e, Blue);
  b^[TRUE] := 11; c^[CHR(201)] := 21; e^[Blue] := 31;
  WRITELN(UPPER(b^), ' ', UPPER(c^), ' ', UPPER(e^));
  WRITELN(b^[TRUE], ' ', c^[CHR(201)], ' ', e^[Blue]);
  w := UNSAFESUPER(PWords, ADR backing, wordlow, 60000);
  i := 60000; w^[i] := 7;
  WRITELN(UPPER(w^), ' ', w^[i]);
  wideptr := UNSAFESUPER(PWide, ADR widebacking, -32767, 32767);
  i := 32767; wideptr^[i] := 8; { valid offset 65534, not a signed i16 GEP }
  WRITELN(LOWER(wideptr^), ' ', UPPER(wideptr^), ' ', wideptr^[i]);
  DISPOSE(b); DISPOSE(c); DISPOSE(e)
END.
