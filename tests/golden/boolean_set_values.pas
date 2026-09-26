PROGRAM BooleanSetValues(OUTPUT);
CONST Yes = TRUE;
TYPE BoolSet = SET OF BOOLEAN;
VAR
  bs: BoolSet;
  flag, lo, hi: BOOLEAN;
  elementCalls, lowCalls, highCalls: INTEGER;

FUNCTION Element(input: BOOLEAN): BOOLEAN;
BEGIN
  elementCalls := elementCalls + 1;
  Element := input
END;

FUNCTION LowBound(input: BOOLEAN): BOOLEAN;
BEGIN
  lowCalls := lowCalls + 1;
  LowBound := input
END;

FUNCTION HighBound(input: BOOLEAN): BOOLEAN;
BEGIN
  highCalls := highCalls + 1;
  HighBound := input
END;

BEGIN
  bs := [FALSE];
  WRITELN('false ', bs = [0]);
  bs := [TRUE];
  WRITELN('true ', bs = [1]);
  bs := [FALSE, TRUE];
  WRITELN('both ', bs = [0, 1]);
  flag := FALSE;
  bs := [flag];
  WRITELN('variable false ', bs = [0]);
  flag := TRUE;
  bs := [flag];
  WRITELN('variable true ', bs = [1]);
  bs := [Yes];
  WRITELN('constant ', bs = [1]);

  bs := [FALSE..TRUE];
  WRITELN('range ', bs = [0, 1]);
  bs := [TRUE..FALSE];
  WRITELN('reversed range ', bs = []);
  lo := FALSE;
  hi := TRUE;
  bs := [lo..hi];
  WRITELN('variable range ', bs = [0, 1]);
  lo := TRUE;
  hi := FALSE;
  bs := [lo..hi];
  WRITELN('variable reversed range ', bs = []);

  elementCalls := 0;
  bs := [Element(TRUE)];
  WRITELN('element calls ', bs = [1], ' ', elementCalls);
  lowCalls := 0;
  highCalls := 0;
  bs := [LowBound(FALSE)..HighBound(TRUE)];
  WRITELN('range calls ', bs = [0, 1], ' ', lowCalls, ' ', highCalls);
  lowCalls := 0;
  highCalls := 0;
  bs := [LowBound(TRUE)..HighBound(FALSE)];
  WRITELN('reversed range calls ', bs = [], ' ', lowCalls, ' ', highCalls);

  elementCalls := 0;
  lowCalls := 0;
  highCalls := 0;
  bs := [Element(FALSE), LowBound(TRUE)..HighBound(FALSE)];
  WRITELN('mixed calls ', bs = [0], ' ', elementCalls, ' ', lowCalls, ' ', highCalls);

  bs := [FALSE];
  elementCalls := 0;
  bs := bs + [Element(TRUE)];
  WRITELN('union ', bs = [0, 1], ' ', elementCalls)
END.
