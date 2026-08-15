(* should_fail: return_stmt = "RETURN" only; no expression. (errors 185/186) *)
PROGRAM P;
BEGIN
  RETURN 42
END.
