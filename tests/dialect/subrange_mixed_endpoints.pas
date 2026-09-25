{ Both ends of a subrange must have the same ordinal type. FALSE..2 used to
  be accepted, typed and stored from its low end alone, so UPPER printed
  FALSE; 'a'..150 took a non-character upper bound. An array index range
  and a set base get the same check. }
PROGRAM SubrangeMixedEndpoints(OUTPUT);
TYPE
  MixedBool = FALSE..2;
  MixedChar = 'a'..150;
VAR
  a: ARRAY[1..'z'] OF INTEGER;
  s: SET OF 'a'..9;
BEGIN
END.
