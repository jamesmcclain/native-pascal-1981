(* should_fail: UNTIL outside REPEAT must not stall the parser. *)
PROGRAM StrayUntil;
BEGIN
  x := 1;
  UNTIL x > 0;
END.
