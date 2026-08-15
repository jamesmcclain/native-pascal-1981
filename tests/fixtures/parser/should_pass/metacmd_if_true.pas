(* $IF with a true (>0) constant includes the then-branch. *)
PROGRAM IfTrue;
VAR x: INTEGER;
BEGIN
  {$IF 1 $THEN}
  x := 1
  {$END}
END.
