(* Nested $IF: inner false block must not confuse the outer $END. *)
PROGRAM IfNested;
VAR x: INTEGER;
BEGIN
  {$IF 1 $THEN}
    {$IF 0 $THEN}
    GARBAGE %%%
    {$ELSE}
    x := 10
    {$END}
  {$END}
END.
