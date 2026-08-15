(* should_pass: NOT belongs in `factor`, so it may follow a mul/add op. *)
PROGRAM P;
VAR a, b : BOOLEAN;
BEGIN
  IF a AND NOT b THEN a := b
END.
