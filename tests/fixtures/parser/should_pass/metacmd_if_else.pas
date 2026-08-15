(* $IF/$ELSE/$END: true condition takes then-branch, skips else-branch. *)
PROGRAM IfElse;
VAR x: INTEGER;
BEGIN
  {$IF 1 $THEN}
  x := 1
  {$ELSE}
  THIS IS GARBAGE AND MUST NOT PARSE %%%
  {$END}
END.
