PROGRAM checked;
PROCEDURE recurse(n: INTEGER);
VAR x: INTEGER; b: BOOLEAN; c: CHAR;
BEGIN
  {$INITCK-} x := n;
  {$INITCK+} b := x >= 0; c := 'a';
  IF b THEN WRITELN(x, c);
  {$INITCK-} IF n > 0 THEN recurse(n - 1)
END;
PROCEDURE values;
VAR x, unwritten: INTEGER; b: BOOLEAN;
BEGIN
  {$INITCK-} x := 0;
  {$INITCK+} WRITELN(x);
  { Full native signed range: IBM compatibility is fun, not pathology.
    INITCK must not reserve or reject the old sentinel's stored bits. }
  x := -32768; WRITELN(x);
  b := FALSE;
  IF b AND THEN (unwritten = 1) THEN x := 9;
  IF TRUE OR ELSE (unwritten = 1) THEN x := x;
  IF b THEN x := 9 ELSE x := 7;
  WRITELN(x + 1);
  {$PUSH} {$INITCK-} x := 11; {$POP} WRITELN(x);
  {$DEBUG+} {$INITCK-} x := 13; {$INITCK+} WRITELN(x);
  {$INITCK-}
END;
PROCEDURE flow(stop: BOOLEAN);
VAR x: INTEGER; b: BOOLEAN;
BEGIN
  {$INITCK-} IF stop THEN RETURN;
  {$INITCK+}
  x := 0; b := FALSE;
  WHILE b DO x := 99;
  REPEAT x := x + 1 UNTIL x = 2;
  WRITELN(x);
  {$PUSH} {$INITCK-}
  {$PUSH} {$DEBUG+} WRITELN(x); {$INITCK-} {$POP}
  x := 3;
  {$POP} WRITELN(x);
  RETURN;
  WRITELN('unreachable')
  {$INITCK-}
END;
BEGIN values; recurse(2); recurse(1); flow(TRUE); flow(FALSE); flow(TRUE); flow(FALSE) END.
