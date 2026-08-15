(* $IF false: skips then-branch garbage, parses else-branch. *)
PROGRAM IfFalseElse;
VAR x: INTEGER;
BEGIN
  {$IF 0 $THEN}
  @@@@@@ GARBAGE @@@@@@
  {$ELSE}
  x := 2
  {$END}
END.
