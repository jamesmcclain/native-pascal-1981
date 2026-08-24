(* should_fail: OTHERWISE outside CASE must not stall the parser. *)
PROGRAM StrayOtherwise;
BEGIN
  x := 1;
  OTHERWISE x := 2;
END.
