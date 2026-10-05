PROGRAM rangeck_scope;
{$INITCK-}
TYPE small = 1..2;
VAR i: small; x: INTEGER; c: CHAR;
FUNCTION Identity(n: small): INTEGER;
BEGIN Identity := n END;
BEGIN
  c := 'a';
  {$RANGECK-} x := 0;
  {$RANGECK+} FOR i := {$RANGECK-} 1 TO 2 DO WRITELN(i);
  {$RANGECK+} CASE x OF 0: {$RANGECK-} x := 0 END;
  {$RANGECK+} IF SUCC({$RANGECK-} c) = 'b' THEN WRITELN('yes');
  {$RANGECK-} IF SUCC({$RANGECK+} c) = 'b' THEN WRITELN('yes');
  {$RANGECK+} IF Identity({$RANGECK-} 2) = 2 THEN WRITELN('call');
  {$RANGECK-} IF Identity({$RANGECK+} 2) = 2 THEN WRITELN('off');
  {$RANGECK+} FOR i := 1 TO 2 DO {$RANGECK-} WRITELN(i);
  {$RANGECK-} FOR i := 1 TO 2 DO {$RANGECK+} WRITELN(i)
END.
