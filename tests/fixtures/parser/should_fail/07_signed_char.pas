(* should_fail: sign prefix applies to numeric constants only, not char. *)
PROGRAM P;
CONST C = -'A';
BEGIN
END.
