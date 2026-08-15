(* $IF with a false (0) constant skips the then-branch entirely.
   The skipped text contains deliberate syntax garbage that must not
   be parsed. *)
PROGRAM IfFalse;
VAR x: INTEGER;
BEGIN
  {$IF 0 $THEN}
  THIS IS NOT VALID PASCAL @@@
  {$END}
  x := 99
END.
