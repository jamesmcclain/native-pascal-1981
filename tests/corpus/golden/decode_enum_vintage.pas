{ DIALECT: vintage }
{ OPT: 0 1 2 3 }
PROGRAM decode_enum_vintage;
{ Vintage READ accepts an enumerated value only as its ordinal, so DECODE
  does; BOOLEAN keeps its names in both dialects. }
{$RANGECK-}
TYPE color = (red, green, blue);
     warm = red..green;
VAR e: color; w: warm; b: BOOLEAN;
BEGIN
  e := red;
  WRITELN(DECODE('1', e), ' ', ORD(e));
  WRITELN(DECODE(' 2 ', e), ' ', ORD(e));
  WRITELN(DECODE('green', e), ' ', ORD(e));
  WRITELN(DECODE('3', e), ' ', ORD(e));
  w := red;
  WRITELN(DECODE('1', w), ' ', ORD(w));
  WRITELN(DECODE('2', w), ' ', ORD(w));
  b := FALSE;
  WRITELN(DECODE('True', b), ' ', b);
  WRITELN(DECODE('0', b), ' ', b);
END.
