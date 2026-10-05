{ An inner save/restore stays on; POP the save made in the other include. }
{$PUSH,MATHCK-}
x := ABS(a);
{$POP}
x := SUCC(a);
{$POP}
