(* should_pass: enum_type is a first-class `type`. *)
PROGRAM P;
TYPE COLOR = (RED, GREEN, BLUE);
VAR  C : COLOR;
BEGIN
  C := RED
END.
