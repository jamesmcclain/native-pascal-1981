{ DIALECT: extended }
{ CHECK-STAGES: lexer parser }
{ CHECK-FAIL: Parser Error: expected constant }
(* should_fail: the ".. *" upper bound is only valid for SUPER ARRAY. *)
PROGRAM P;
TYPE A = ARRAY [0..*] OF INTEGER;
BEGIN
END.
