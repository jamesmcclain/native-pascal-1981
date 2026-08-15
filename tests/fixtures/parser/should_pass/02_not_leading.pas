(* should_pass: NOT at the head of a simple_expr. *)
PROGRAM P;
VAR a : BOOLEAN;
BEGIN
  IF NOT a THEN a := a
END.
